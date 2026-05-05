-- ============================================================================
-- Drop batches.fees (Sprint-1 leftover, redundant with fee_structures), and
-- add assign_fee_to_batch() RPC for bulk-assigning a fee structure to every
-- active enrollment in a batch.
--
-- The view batches_with_counts uses `select b.*`, so we drop + recreate it
-- to keep its column list aligned with the new shape.
-- ============================================================================

drop view if exists public.batches_with_counts;

alter table public.batches drop column if exists fees;

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

-- ============================================================================
-- assign_fee_to_batch(p_fee_id, p_batch_id, p_start_date, p_billing_day)
--
-- Inserts a student_fee_assignment for every active enrollment in the batch
-- that doesn't already have one for this fee at this start_date. Returns
-- the number of rows actually created.
--
-- SECURITY DEFINER so a caller can write to student_fee_assignments without
-- needing direct INSERT permission via RLS, but we re-assert tenancy: the
-- fee, batch, and caller must all share academy_id (or caller is super_admin).
-- ============================================================================

create or replace function public.assign_fee_to_batch(
  p_fee_id uuid,
  p_batch_id uuid,
  p_start_date date default current_date,
  p_billing_day int default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fee_academy uuid;
  v_batch_academy uuid;
  v_caller_academy uuid := public.current_user_academy_id();
  v_inserted int;
begin
  select academy_id into v_fee_academy
    from public.fee_structures where id = p_fee_id;
  select academy_id into v_batch_academy
    from public.batches where id = p_batch_id;

  if v_fee_academy is null or v_batch_academy is null then
    raise exception 'fee_structure or batch not found';
  end if;
  if v_fee_academy <> v_batch_academy then
    raise exception 'fee and batch belong to different academies';
  end if;
  if not public.is_super_admin()
     and v_caller_academy is distinct from v_fee_academy then
    raise exception 'cross-tenant assignment not allowed';
  end if;
  if not (public.is_super_admin() or public.has_admin_or_higher()) then
    raise exception 'admin-or-higher required';
  end if;

  insert into public.student_fee_assignments
    (academy_id, student_id, fee_structure_id, start_date, billing_day)
  select v_fee_academy, e.student_id, p_fee_id, p_start_date, p_billing_day
    from public.batch_enrollments e
    where e.batch_id = p_batch_id
      and e.enrollment_status = 'active'
  on conflict (student_id, fee_structure_id, start_date) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

grant execute on function public.assign_fee_to_batch(uuid, uuid, date, int)
  to authenticated;
