-- ============================================================================
-- Sprint 5 — Analytics materialized views.
--
-- Refreshed by the `analytics-aggregations` Edge Function on a cron. KPI
-- panels read these views directly. Each view is academy-scoped and
-- preserves academy_id so RLS can apply via wrapper view + policy below.
--
-- Views:
--   mv_revenue_by_month         — paid amount + invoice counts per month
--   mv_enrollment_by_month      — new enrollments per month
--   mv_lead_funnel_summary      — leads grouped by status / source
--   mv_batch_utilization        — capacity vs. active enrollments
--   mv_collection_summary       — academy-level outstanding vs. collected
--
-- We expose them through SECURITY INVOKER views named without the `mv_`
-- prefix; the wrapper views inherit RLS from their underlying tables via
-- the academy_id column.
-- ============================================================================

create materialized view if not exists public.mv_revenue_by_month as
select
  i.academy_id,
  date_trunc('month', i.issued_at)::date as month_start,
  count(*) filter (where i.status = 'paid')::int       as paid_count,
  count(*)::int                                        as invoice_count,
  coalesce(sum(i.amount_paid), 0)::numeric(12, 2)      as collected,
  coalesce(sum(i.amount), 0)::numeric(12, 2)           as billed,
  coalesce(sum(i.amount - i.amount_paid)
           filter (where i.status in ('issued', 'partial', 'overdue')),
           0)::numeric(12, 2)                          as outstanding
from public.invoices i
group by i.academy_id, date_trunc('month', i.issued_at);

create unique index if not exists idx_mv_revenue_by_month
  on public.mv_revenue_by_month(academy_id, month_start);

create materialized view if not exists public.mv_enrollment_by_month as
select
  e.academy_id,
  date_trunc('month', e.enrolled_at)::date as month_start,
  count(*)::int as enrollment_count
from public.batch_enrollments e
where e.enrollment_status = 'active'
group by e.academy_id, date_trunc('month', e.enrolled_at);

create unique index if not exists idx_mv_enrollment_by_month
  on public.mv_enrollment_by_month(academy_id, month_start);

create materialized view if not exists public.mv_lead_funnel_summary as
select
  l.academy_id,
  l.status,
  l.source,
  count(*)::int as cnt
from public.leads l
group by l.academy_id, l.status, l.source;

create unique index if not exists idx_mv_lead_funnel_summary
  on public.mv_lead_funnel_summary(academy_id, status, source);

create materialized view if not exists public.mv_batch_utilization as
select
  b.academy_id,
  b.id as batch_id,
  b.name,
  b.capacity,
  coalesce(c.cnt, 0)::int as enrolled
from public.batches b
left join (
  select batch_id, count(*) as cnt
  from public.batch_enrollments
  where enrollment_status = 'active'
  group by batch_id
) c on c.batch_id = b.id
where b.is_active;

create unique index if not exists idx_mv_batch_utilization
  on public.mv_batch_utilization(academy_id, batch_id);

create materialized view if not exists public.mv_collection_summary as
select
  i.academy_id,
  count(*) filter (where i.status in ('issued', 'partial', 'overdue'))::int as outstanding_count,
  coalesce(sum(i.amount - i.amount_paid)
           filter (where i.status in ('issued', 'partial', 'overdue')),
           0)::numeric(12, 2) as outstanding_amount,
  count(*) filter (where i.status = 'overdue')::int as overdue_count,
  coalesce(sum(i.amount_paid), 0)::numeric(12, 2) as collected_total,
  count(*) filter (where i.status = 'paid')::int as paid_count
from public.invoices i
group by i.academy_id;

create unique index if not exists idx_mv_collection_summary
  on public.mv_collection_summary(academy_id);

-- ============================================================================
-- refresh_analytics() — concurrently refreshes all five views; called by the
-- `analytics-aggregations` Edge Function.
-- ============================================================================

create or replace function public.refresh_analytics()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.mv_revenue_by_month;
  refresh materialized view concurrently public.mv_enrollment_by_month;
  refresh materialized view concurrently public.mv_lead_funnel_summary;
  refresh materialized view concurrently public.mv_batch_utilization;
  refresh materialized view concurrently public.mv_collection_summary;
end;
$$;

revoke all on function public.refresh_analytics() from public;
-- only service-role / super_admin can refresh; not granted to authenticated.

-- ============================================================================
-- RLS-friendly wrapper views (security invoker). Materialized views can't
-- have RLS, so we wrap them in a view that filters by current_user_academy_id.
-- super_admin sees everything via the OR clause.
-- ============================================================================

create or replace view public.analytics_revenue_by_month
  with (security_invoker = on) as
select * from public.mv_revenue_by_month
where public.is_super_admin()
   or academy_id = public.current_user_academy_id();

create or replace view public.analytics_enrollment_by_month
  with (security_invoker = on) as
select * from public.mv_enrollment_by_month
where public.is_super_admin()
   or academy_id = public.current_user_academy_id();

create or replace view public.analytics_lead_funnel_summary
  with (security_invoker = on) as
select * from public.mv_lead_funnel_summary
where public.is_super_admin()
   or academy_id = public.current_user_academy_id();

create or replace view public.analytics_batch_utilization
  with (security_invoker = on) as
select * from public.mv_batch_utilization
where public.is_super_admin()
   or academy_id = public.current_user_academy_id();

create or replace view public.analytics_collection_summary
  with (security_invoker = on) as
select * from public.mv_collection_summary
where public.is_super_admin()
   or academy_id = public.current_user_academy_id();

grant select on public.analytics_revenue_by_month       to authenticated;
grant select on public.analytics_enrollment_by_month    to authenticated;
grant select on public.analytics_lead_funnel_summary    to authenticated;
grant select on public.analytics_batch_utilization      to authenticated;
grant select on public.analytics_collection_summary     to authenticated;
