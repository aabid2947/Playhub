-- ============================================================================
-- students.fee_overdue trigger regression test
-- (20260608000300_student_fee_overdue_flag.sql).
--
-- The trigger on invoices keeps students.fee_overdue in sync with whether the
-- student has any OVERDUE invoice. Runs as superuser (RLS bypassed) — it tests
-- the trigger maintenance, not the read policy. Transaction + rollback.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner constant uuid := '00000000-0d00-0000-0000-000000000001';
  v_academy uuid;
  v_c1 uuid;
  v_student uuid;
  v_inv uuid;
  v_flag boolean;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values (v_owner, '00000000-0000-0000-0000-000000000000', 'fo-owner@x.invalid',
          'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id)
  values ('Fee-overdue Academy', v_owner) returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1')
  returning id into v_c1;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Dues', 'Kid', 'Parent') returning id into v_student;

  -- Baseline: no invoices → flag false.
  select fee_overdue into v_flag from public.students where id = v_student;
  if v_flag then raise exception 'FAIL: flag true with no invoices'; end if;

  -- An ISSUED (not overdue) invoice must NOT flag.
  insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount, status)
  values (v_academy, v_student, 'INV-A', current_date + 5, 1000, 'issued')
  returning id into v_inv;
  select fee_overdue into v_flag from public.students where id = v_student;
  if v_flag then raise exception 'FAIL: flag true for a not-yet-overdue invoice'; end if;

  -- Flip it overdue → flag true.
  update public.invoices set status = 'overdue' where id = v_inv;
  select fee_overdue into v_flag from public.students where id = v_student;
  if not v_flag then raise exception 'FAIL: flag not set when invoice overdue'; end if;

  -- Pay it (status → paid) → flag clears.
  update public.invoices set status = 'paid' where id = v_inv;
  select fee_overdue into v_flag from public.students where id = v_student;
  if v_flag then raise exception 'FAIL: flag still set after invoice paid'; end if;

  -- A second overdue invoice re-raises it; deleting it clears it again.
  insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount, status)
  values (v_academy, v_student, 'INV-B', current_date - 5, 500, 'overdue')
  returning id into v_inv;
  select fee_overdue into v_flag from public.students where id = v_student;
  if not v_flag then raise exception 'FAIL: flag not set for second overdue invoice'; end if;

  delete from public.invoices where id = v_inv;
  select fee_overdue into v_flag from public.students where id = v_student;
  if v_flag then raise exception 'FAIL: flag still set after overdue invoice deleted'; end if;

  raise notice 'PASS: fee_overdue tracks overdue invoices (set/clear/delete)';
end $$;

rollback;
