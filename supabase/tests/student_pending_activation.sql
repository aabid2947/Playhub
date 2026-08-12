-- ============================================================================
-- students 'pending' status + activate-on-payment trigger regression test
-- (20260808000000_student_pending_until_paid.sql).
--
-- Asserts:
--   • a student inserted WITHOUT an explicit status defaults to 'pending'
--   • a completed payment flips 'pending' -> 'active'
--   • a non-completed payment does NOT activate
--   • a paused/inactive/graduated student is NOT touched by a payment
--   • a second payment doesn't disturb an already-active student
--
-- Runs as superuser (RLS bypassed) — this tests trigger maintenance, not the
-- read policy. Transaction + rollback; any 'FAIL' aborts.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner constant uuid := '00000000-0e00-0000-0000-000000000001';
  v_academy uuid;
  v_c1 uuid;
  v_pending uuid;
  v_paused uuid;
  v_inv_p uuid;
  v_inv_q uuid;
  v_status text;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values (v_owner, '00000000-0000-0000-0000-000000000000', 'sp-owner@x.invalid',
          'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id)
  values ('Pending-status Academy', v_owner) returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1')
  returning id into v_c1;

  -- ---------- default is 'pending' ------------------------------------------
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'New', 'Joiner', 'Parent') returning id into v_pending;
  select status into v_status from public.students where id = v_pending;
  if v_status <> 'pending' then
    raise exception 'FAIL: new student defaulted to %, expected pending', v_status;
  end if;

  -- ---------- a NON-completed payment must not activate ---------------------
  insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount, status)
  values (v_academy, v_pending, 'INV-P1', current_date + 5, 1000, 'issued')
  returning id into v_inv_p;

  insert into public.payments (academy_id, invoice_id, student_id, amount, method, status)
  values (v_academy, v_inv_p, v_pending, 500, 'cash', 'pending');
  select status into v_status from public.students where id = v_pending;
  if v_status <> 'pending' then
    raise exception 'FAIL: pending payment activated the student (now %)', v_status;
  end if;

  -- ---------- a COMPLETED payment activates ---------------------------------
  insert into public.payments (academy_id, invoice_id, student_id, amount, method, status)
  values (v_academy, v_inv_p, v_pending, 1000, 'cash', 'completed');
  select status into v_status from public.students where id = v_pending;
  if v_status <> 'active' then
    raise exception 'FAIL: completed payment left student as %', v_status;
  end if;

  -- A later payment must not disturb the already-active student.
  insert into public.payments (academy_id, invoice_id, student_id, amount, method, status)
  values (v_academy, v_inv_p, v_pending, 200, 'cash', 'completed');
  select status into v_status from public.students where id = v_pending;
  if v_status <> 'active' then
    raise exception 'FAIL: second payment changed active student to %', v_status;
  end if;

  -- ---------- a deliberate paused/inactive state is respected ---------------
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name, status)
  values (v_academy, v_c1, 'On', 'Break', 'Parent', 'paused') returning id into v_paused;
  insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount, status)
  values (v_academy, v_paused, 'INV-Q1', current_date + 5, 1000, 'issued')
  returning id into v_inv_q;
  insert into public.payments (academy_id, invoice_id, student_id, amount, method, status)
  values (v_academy, v_inv_q, v_paused, 1000, 'cash', 'completed');
  select status into v_status from public.students where id = v_paused;
  if v_status <> 'paused' then
    raise exception 'FAIL: payment overrode a paused student (now %)', v_status;
  end if;

  -- ---------- status flipping to completed later also activates -------------
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Late', 'Clear', 'Parent') returning id into v_pending;
  insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount, status)
  values (v_academy, v_pending, 'INV-P2', current_date + 5, 1000, 'issued')
  returning id into v_inv_p;
  insert into public.payments (academy_id, invoice_id, student_id, amount, method, status)
  values (v_academy, v_inv_p, v_pending, 1000, 'cash', 'pending');
  update public.payments set status = 'completed'
   where invoice_id = v_inv_p and student_id = v_pending;
  select status into v_status from public.students where id = v_pending;
  if v_status <> 'active' then
    raise exception 'FAIL: payment updated to completed left student as %', v_status;
  end if;

  raise notice 'PASS: students default to pending and activate on first completed payment';
end $$;

rollback;
