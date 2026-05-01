-- ============================================================================
-- Sprint 2 — materialized views for dashboards
--
-- - student_attendance_summary: per-student totals + percentage over the
--   last 30 days. Powers parent + admin dashboards without re-aggregating
--   on every load. Refreshed by the `attendance-aggregate` cron.
--
-- - student_performance_trend: per-student rolling average score from the
--   last 5 assessments.
--
-- These are owned by `postgres` and not RLS-able directly; we expose them
-- through plain views (`*_view`) that re-apply the academy_id filter so
-- RLS-bypass cannot leak across tenants.
-- ============================================================================

create materialized view public.student_attendance_summary as
select
  s.academy_id,
  s.id as student_id,
  count(a.id)                                    as total_sessions,
  count(a.id) filter (where a.status = 'present') as present_count,
  count(a.id) filter (where a.status = 'absent')  as absent_count,
  count(a.id) filter (where a.status = 'late')    as late_count,
  count(a.id) filter (where a.status = 'excused') as excused_count,
  case
    when count(a.id) = 0 then null
    else round(
      100.0 * count(a.id) filter (where a.status in ('present','late'))
      / count(a.id),
      1
    )
  end                                             as attendance_pct,
  max(a.date)                                     as last_attended_date,
  now()                                           as refreshed_at
from public.students s
left join public.attendance_records a
  on a.student_id = s.id
  and a.date >= current_date - interval '30 days'
group by s.academy_id, s.id;

create unique index idx_attendance_summary_pk
  on public.student_attendance_summary(student_id);
create index idx_attendance_summary_academy
  on public.student_attendance_summary(academy_id);

-- Tenant-safe wrapper view (RLS doesn't apply to mat-views directly)
create or replace view public.student_attendance_summary_view as
select * from public.student_attendance_summary
where public.is_super_admin()
   or academy_id = public.current_user_academy_id();

grant select on public.student_attendance_summary_view to authenticated;

-- ============================================================================
-- student_performance_trend — last 5 assessments, average score, latest sport
-- ============================================================================

create materialized view public.student_performance_trend as
with ranked as (
  select
    pa.id,
    pa.academy_id,
    pa.student_id,
    pa.assessment_date,
    pa.overall_score,
    pa.sport,
    row_number() over (
      partition by pa.student_id
      order by pa.assessment_date desc, pa.created_at desc
    ) as rn
  from public.performance_assessments pa
)
select
  academy_id,
  student_id,
  count(*)                              as recent_assessments,
  round(avg(overall_score)::numeric, 2) as avg_recent_score,
  max(assessment_date)                  as last_assessed_date,
  -- sport from the most-recent assessment
  (array_agg(sport order by assessment_date desc, id desc)
    filter (where sport is not null))[1] as latest_sport,
  now()                                 as refreshed_at
from ranked
where rn <= 5 and overall_score is not null
group by academy_id, student_id;

create unique index idx_performance_trend_pk
  on public.student_performance_trend(student_id);
create index idx_performance_trend_academy
  on public.student_performance_trend(academy_id);

create or replace view public.student_performance_trend_view as
select * from public.student_performance_trend
where public.is_super_admin()
   or academy_id = public.current_user_academy_id();

grant select on public.student_performance_trend_view to authenticated;

-- ============================================================================
-- Refresh function — called by `attendance-aggregate` Edge Function cron
-- and exposed as RPC for on-demand admin refresh.
-- CONCURRENTLY needs the unique index, which we have on student_id.
-- ============================================================================

create or replace function public.refresh_attendance_aggregates()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.student_attendance_summary;
  refresh materialized view concurrently public.student_performance_trend;
end;
$$;

grant execute on function public.refresh_attendance_aggregates() to authenticated;

-- Initial populate so the views aren't empty before the first cron run.
refresh materialized view public.student_attendance_summary;
refresh materialized view public.student_performance_trend;
