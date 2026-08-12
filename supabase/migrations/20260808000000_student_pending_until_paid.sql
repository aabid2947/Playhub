-- ============================================================================
-- Students start PENDING and activate on their first payment.
--
-- Client decision (ISSUES_2026-08-06 #6): a newly created student should not be
-- "active" from the moment the form is saved. They become active when money
-- actually arrives — and an admin may still flip them active by hand for the
-- cash-in-hand / goodwill cases (the status field stays freely editable).
--
-- Scope notes:
--   * 'pending' is added to the existing status check; nothing is removed, so
--     every current row stays valid.
--   * The column DEFAULT moves 'active' -> 'pending' so non-form insert paths
--     (CSV import, raw API) follow the same rule. Callers that pass an explicit
--     status (seed.sql, the mobile form) are unaffected.
--   * Invoice generation keys off batch_enrollments.enrollment_status, NOT
--     students.status, so a pending student still gets invoiced and can pay —
--     which is what activates them. Don't add a students.status filter there
--     or new students become unbillable and can never leave 'pending'.
-- ============================================================================

alter table public.students
  drop constraint if exists students_status_check;

alter table public.students
  add constraint students_status_check
  check (status in ('pending', 'active', 'inactive', 'paused', 'graduated'));

alter table public.students
  alter column status set default 'pending';

-- ----------------------------------------------------------------------------
-- Activate a pending student the moment a completed payment lands.
--
-- Fires for BOTH money paths, because both end in a payments row: the Razorpay
-- webhook / verify-on-return (service role) and an admin recording a cash,
-- cheque or bank receipt. SECURITY DEFINER so the webhook's service-role
-- context and an admin's JWT both succeed without a students UPDATE policy
-- carve-out.
--
-- Only 'pending' is touched: a paused, inactive or graduated student is a
-- deliberate admin decision and a payment must not silently undo it.
-- ----------------------------------------------------------------------------
create or replace function public.activate_student_on_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed' then
    update public.students
       set status = 'active'
     where id = new.student_id
       and status = 'pending';
  end if;
  return new;
end;
$$;

comment on function public.activate_student_on_payment() is
  'Flips a pending student to active on their first completed payment '
  '(online or manually recorded). Leaves paused/inactive/graduated alone.';

drop trigger if exists trg_activate_student_on_payment on public.payments;
create trigger trg_activate_student_on_payment
  after insert or update of status on public.payments
  for each row
  execute function public.activate_student_on_payment();
