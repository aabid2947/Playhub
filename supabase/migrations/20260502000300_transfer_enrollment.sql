-- ============================================================================
-- transfer_enrollment(p_enrollment_id, p_target_batch_id)
--
-- Atomically moves a student from one batch to another:
--   1. Withdraw the source enrollment.
--   2. Insert a new active enrollment in the target batch (or promote an
--      existing withdrawn one back to active).
-- Both steps happen in a single transaction so a partial failure can never
-- leave the student in a half-transferred state.
-- ============================================================================

create or replace function public.transfer_enrollment(
  p_enrollment_id uuid,
  p_target_batch_id uuid
)
returns public.batch_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.batch_enrollments;
  v_target_academy uuid;
  v_existing public.batch_enrollments;
  v_result public.batch_enrollments;
begin
  -- Source enrollment
  select * into v_source
  from public.batch_enrollments
  where id = p_enrollment_id;
  if v_source is null then
    raise exception 'Enrollment not found';
  end if;

  -- Target batch must exist and be in the same academy (cross-tenant move
  -- would silently break RLS expectations).
  select academy_id into v_target_academy
  from public.batches
  where id = p_target_batch_id;
  if v_target_academy is null then
    raise exception 'Target batch not found';
  end if;
  if v_target_academy <> v_source.academy_id then
    raise exception 'Cannot transfer across academies';
  end if;

  -- Withdraw source
  update public.batch_enrollments
  set enrollment_status = 'withdrawn'
  where id = p_enrollment_id;

  -- Look for an existing enrollment in the target batch (e.g. previously
  -- withdrawn). The unique (batch_id, student_id) constraint forces this.
  select * into v_existing
  from public.batch_enrollments
  where batch_id = p_target_batch_id and student_id = v_source.student_id;

  if v_existing is null then
    insert into public.batch_enrollments
      (academy_id, batch_id, student_id, enrollment_status)
    values
      (v_source.academy_id, p_target_batch_id, v_source.student_id, 'active')
    returning * into v_result;
  else
    update public.batch_enrollments
    set enrollment_status = 'active'
    where id = v_existing.id
    returning * into v_result;
  end if;

  return v_result;
end;
$$;

revoke all on function public.transfer_enrollment(uuid, uuid) from public;
grant execute on function public.transfer_enrollment(uuid, uuid)
  to authenticated;
