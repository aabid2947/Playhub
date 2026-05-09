-- ============================================================================
-- Polish phase 3 cleanup — drop the legacy free-text `sport` columns now
-- that every Flutter form writes sport_id and every display site reads
-- through `sportDisplayProvider`. Also drops:
--
--   * academies.sports_offered text[]    — replaced by academy_sports
--   * coaches.specialization is kept     — repurposed as "sub-specialty"
--   * match_sport_text(text)             — backfill helper, no longer used
--
-- The student_performance_trend materialized view referenced
-- performance_assessments.sport, so we drop+recreate it on sport_id.
-- ============================================================================

-- 1) Drop dependent views first so the column drops don't trip on them.
--    Both views are recreated below.
drop materialized view if exists public.student_performance_trend cascade;
drop view if exists public.batches_with_counts;

-- 2) Drop the columns.
alter table public.students                drop column if exists sport;
alter table public.batches                 drop column if exists sport;
alter table public.leads                   drop column if exists sport;
alter table public.events                  drop column if exists sport;
alter table public.performance_assessments drop column if exists sport;
alter table public.fee_structures          drop column if exists sport;

alter table public.academies               drop column if exists sports_offered;

-- 3) Drop the matcher helper, no longer needed.
drop function if exists public.match_sport_text(text);

-- 4) Re-create the matview using sport_id, with the same indexes + wrapper
-- view. Refresh function `refresh_student_performance_trend` continues to
-- work because the matview keeps the same name.
create materialized view public.student_performance_trend as
with ranked as (
  select
    pa.id,
    pa.academy_id,
    pa.student_id,
    pa.assessment_date,
    pa.overall_score,
    pa.sport_id,
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
  -- sport_id from the most-recent assessment for the student
  (array_agg(sport_id order by assessment_date desc, id desc)
    filter (where sport_id is not null))[1] as latest_sport_id,
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

-- 5) Re-create batches_with_counts (was `select b.*, ...`, expanded so
--    Postgres doesn't consider the dropped column a dependency).
create or replace view public.batches_with_counts as
select
  b.*,
  coalesce(e.cnt, 0)::int as enrolled_count
from public.batches b
left join (
  select batch_id, count(*)::int as cnt
  from public.batch_enrollments
  where enrollment_status = 'active'
  group by batch_id
) e on e.batch_id = b.id;

grant select on public.batches_with_counts to authenticated;
