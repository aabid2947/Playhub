-- ============================================================================
-- Phase 4 regression — center-scoped finance
-- (20260607000400_center_scoped_finance.sql).
--
-- One academy, centers C1/C2. studentA in C1, studentB in C2. invoiceA/payment
-- for studentA; invoiceB for studentB. A parent linked to studentA.
--
-- Asserts:
--   • center_admin (C1): writes + reads ONLY own-center (studentA) finance;
--     cannot touch studentB; cannot create a refund (admin+).
--   • parent: sees their own student's invoice, not the other center's.
--   • coach: sees no finance.
--   • owner: sees both; can create a refund.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner constant uuid := '00000000-0f00-0000-0000-000000000001';
  v_ca1   constant uuid := '00000000-0f00-0000-0000-000000000002';
  v_co    constant uuid := '00000000-0f00-0000-0000-000000000003';
  v_par   constant uuid := '00000000-0f00-0000-0000-000000000004';
  v_academy uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_sA uuid;
  v_sB uuid;
  v_iA uuid;
  v_iB uuid;
  v_pA uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'fin-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'fin-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_co,    '00000000-0000-0000-0000-000000000000', 'fin-co@x.invalid',    'authenticated', 'authenticated', now(), now(), now()),
    (v_par,   '00000000-0000-0000-0000-000000000000', 'fin-par@x.invalid',   'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id) values ('Finance Academy', v_owner)
  returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1') returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_academy, 'C2') returning id into v_c2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O', 'fin-owner@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'CA', '1', 'fin-ca1@x.invalid'),
    (v_co,    'coach',         v_academy, v_c1, 'Co', 'X', 'fin-co@x.invalid'),
    (v_par,   'parent',        v_academy, null, 'Par', 'Ent', 'fin-par@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Stu', 'A', 'P') returning id into v_sA;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c2, 'Stu', 'B', 'P') returning id into v_sB;

  insert into public.parent_links (academy_id, parent_user_id, student_id, is_primary)
  values (v_academy, v_par, v_sA, true);

  insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount)
  values (v_academy, v_sA, 'INV-A-1', current_date + 7, 1000) returning id into v_iA;
  insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount)
  values (v_academy, v_sB, 'INV-B-1', current_date + 7, 1000) returning id into v_iB;

  insert into public.payments (academy_id, invoice_id, student_id, amount, method)
  values (v_academy, v_iA, v_sA, 1000, 'cash') returning id into v_pA;

  perform set_config('fin.academy', v_academy::text, true);
  perform set_config('fin.sA', v_sA::text, true);
  perform set_config('fin.sB', v_sB::text, true);
  perform set_config('fin.iA', v_iA::text, true);
  perform set_config('fin.iB', v_iB::text, true);
  perform set_config('fin.pA', v_pA::text, true);
end $$;

-- ---------- center_admin (C1): own-center finance only ----------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000002';  -- ca1

do $$
declare
  v_academy uuid := current_setting('fin.academy')::uuid;
  v_sA uuid := current_setting('fin.sA')::uuid;
  v_sB uuid := current_setting('fin.sB')::uuid;
  v_iA uuid := current_setting('fin.iA')::uuid;
  v_iB uuid := current_setting('fin.iB')::uuid;
  v_pA uuid := current_setting('fin.pA')::uuid;
  v_cnt int;
  v_caught boolean := false;
begin
  -- Create an invoice for own-center student → allowed.
  begin
    insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount)
    values (v_academy, v_sA, 'INV-CA-OK', current_date + 7, 500);
  exception when others then
    raise exception 'FAIL: center_admin could not invoice own-center student: %', SQLERRM;
  end;

  -- Create an invoice for other-center student → denied.
  v_caught := false;
  begin
    insert into public.invoices (academy_id, student_id, invoice_number, due_date, base_amount)
    values (v_academy, v_sB, 'INV-CA-BAD', current_date + 7, 500);
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: center_admin invoiced an other-center student';
  end if;

  -- Reads: sees own-center invoice, NOT the other center's.
  select count(*) into v_cnt from public.invoices where id = v_iA;
  if v_cnt <> 1 then raise exception 'FAIL: center_admin cannot see own-center invoice'; end if;
  select count(*) into v_cnt from public.invoices where id = v_iB;
  if v_cnt <> 0 then raise exception 'FAIL: center_admin can see another centre''s invoice'; end if;

  -- Refund is admin+ only → denied.
  v_caught := false;
  begin
    insert into public.refunds (academy_id, payment_id, amount)
    values (v_academy, v_pA, 100);
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: center_admin created a refund (must be admin+)';
  end if;

  raise notice 'PASS: center_admin — own-center finance only, no refunds';
end $$;

-- ---------- parent: only their own student's invoice ------------------------

set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000004';  -- parent of sA

do $$
declare
  v_iA uuid := current_setting('fin.iA')::uuid;
  v_iB uuid := current_setting('fin.iB')::uuid;
  v_cnt int;
begin
  select count(*) into v_cnt from public.invoices where id = v_iA;
  if v_cnt <> 1 then raise exception 'FAIL: parent cannot see own child invoice'; end if;
  select count(*) into v_cnt from public.invoices where id = v_iB;
  if v_cnt <> 0 then raise exception 'FAIL: parent can see an unrelated invoice'; end if;
  raise notice 'PASS: parent — sees only their own child''s invoice';
end $$;

-- ---------- coach: no finance visibility ------------------------------------

set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000003';  -- coach

do $$
declare
  v_academy uuid := current_setting('fin.academy')::uuid;
  v_cnt int;
begin
  select count(*) into v_cnt from public.invoices where academy_id = v_academy;
  if v_cnt <> 0 then raise exception 'FAIL: coach can read invoices (finance is not theirs)'; end if;
  raise notice 'PASS: coach — no finance visibility';
end $$;

-- ---------- owner: sees all + can refund ------------------------------------

set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000001';  -- owner

do $$
declare
  v_academy uuid := current_setting('fin.academy')::uuid;
  v_pA uuid := current_setting('fin.pA')::uuid;
  v_cnt int;
begin
  select count(*) into v_cnt from public.invoices where academy_id = v_academy;
  if v_cnt < 2 then raise exception 'FAIL: owner cannot see all academy invoices'; end if;

  begin
    insert into public.refunds (academy_id, payment_id, amount)
    values (v_academy, v_pA, 100);
  exception when others then
    raise exception 'FAIL: owner could not create a refund: %', SQLERRM;
  end;
  raise notice 'PASS: owner — sees all finance + can refund';
end $$;

reset role;
rollback;

\echo 'All finance-scope tests passed.'
