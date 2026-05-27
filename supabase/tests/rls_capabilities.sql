-- ============================================================================
-- Role-capability regression test (the "scope + management ladder").
--
-- One academy, two centers (C1, C2), one user per staff role. Asserts the
-- per-role write matrix introduced in 20260527000000_role_capabilities.sql:
--
--   • trainer    → attendance on OWN batch yes; performance NO
--   • coach      → attendance + performance on OWN batch; other batch NO
--   • center_admin (C1) → manage students in C1 yes; C2 no
--   • head_coach (C1)   → manage batches in C1 yes; C2 no; students NO
--   • coach      → cannot create students or batches
--
-- Runs in a transaction and rolls back. Any 'FAIL' aborts. Same harness as
-- rls_tenancy.sql: impersonate by setting request.jwt.claim.sub.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

-- ---------- Setup (superuser; RLS bypassed) ---------------------------------

do $$
declare
  v_owner constant uuid := '00000000-0e00-0000-0000-000000000001';
  v_admin constant uuid := '00000000-0e00-0000-0000-000000000002';
  v_ca1   constant uuid := '00000000-0e00-0000-0000-000000000003';
  v_hc1   constant uuid := '00000000-0e00-0000-0000-000000000004';
  v_co1   constant uuid := '00000000-0e00-0000-0000-000000000005';
  v_tr1   constant uuid := '00000000-0e00-0000-0000-000000000006';
  v_academy uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_coach_co1 uuid;
  v_coach_tr1 uuid;
  v_coach_other uuid;
  v_b1 uuid;  -- C1, owned by co1
  v_b2 uuid;  -- C1, owned by tr1
  v_b3 uuid;  -- C2, owned by neither
  v_s1 uuid;  -- C1
  v_s2 uuid;  -- C2
begin
  -- auth.users → triggers stub public.users rows (role student, academy null,
  -- allowed since the academy-required check was relaxed in Sprint 0).
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'cap-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'cap-admin@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'cap-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_hc1,   '00000000-0000-0000-0000-000000000000', 'cap-hc1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_co1,   '00000000-0000-0000-0000-000000000000', 'cap-co1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_tr1,   '00000000-0000-0000-0000-000000000000', 'cap-tr1@x.invalid',   'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id)
  values ('Capability Academy', v_owner)
  returning id into v_academy;

  insert into public.centers (academy_id, name) values (v_academy, 'C1')
  returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_academy, 'C2')
  returning id into v_c2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O', 'cap-owner@x.invalid'),
    (v_admin, 'academy_admin', v_academy, null, 'Admin', 'A', 'cap-admin@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'Center', 'Admin1', 'cap-ca1@x.invalid'),
    (v_hc1,   'head_coach',    v_academy, v_c1, 'Head', 'Coach1', 'cap-hc1@x.invalid'),
    (v_co1,   'coach',         v_academy, v_c1, 'Coach', 'One', 'cap-co1@x.invalid'),
    (v_tr1,   'trainer',       v_academy, v_c1, 'Trainer', 'One', 'cap-tr1@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id,
        center_id = excluded.center_id;

  -- Coaches: co1 + tr1 have logins (user_id); a third coach in C2 has none.
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_co1, 'Coach', 'One') returning id into v_coach_co1;
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_tr1, 'Trainer', 'One') returning id into v_coach_tr1;
  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c2, 'Other', 'Coach') returning id into v_coach_other;

  insert into public.batches (academy_id, center_id, coach_id, name)
  values (v_academy, v_c1, v_coach_co1, 'B1') returning id into v_b1;
  insert into public.batches (academy_id, center_id, coach_id, name)
  values (v_academy, v_c1, v_coach_tr1, 'B2') returning id into v_b2;
  insert into public.batches (academy_id, center_id, coach_id, name)
  values (v_academy, v_c2, v_coach_other, 'B3') returning id into v_b3;

  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Sam', 'C1', 'Parent 1') returning id into v_s1;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c2, 'Sara', 'C2', 'Parent 2') returning id into v_s2;

  perform set_config('cap.academy', v_academy::text, true);
  perform set_config('cap.c1', v_c1::text, true);
  perform set_config('cap.c2', v_c2::text, true);
  perform set_config('cap.b1', v_b1::text, true);
  perform set_config('cap.b2', v_b2::text, true);
  perform set_config('cap.b3', v_b3::text, true);
  perform set_config('cap.s1', v_s1::text, true);
  perform set_config('cap.s2', v_s2::text, true);

  raise notice '[cap setup] academy %, centers % %', v_academy, v_c1, v_c2;
end $$;

-- ---------- C1: trainer — attendance on own batch yes, performance no -------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0e00-0000-0000-000000000006';  -- tr1

do $$
declare
  v_academy uuid := current_setting('cap.academy')::uuid;
  v_b2 uuid := current_setting('cap.b2')::uuid;
  v_s1 uuid := current_setting('cap.s1')::uuid;
  v_caught boolean := false;
begin
  -- Own batch attendance → allowed.
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b2, v_s1, current_date, 'present', 'manual');
  exception when others then
    raise exception 'FAIL: trainer could not mark attendance on own batch: %', SQLERRM;
  end;

  -- Performance → denied (trainer excluded).
  begin
    insert into public.performance_assessments
      (academy_id, student_id, batch_id, assessment_date, overall_score)
    values (v_academy, v_s1, v_b2, current_date, 7.0);
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: trainer was able to record a performance assessment';
  end if;
  raise notice 'PASS: trainer — attendance allowed, performance blocked';
end $$;

-- ---------- C2: coach — own batch ok, other batch blocked -------------------

set local request.jwt.claim.sub = '00000000-0e00-0000-0000-000000000005';  -- co1

do $$
declare
  v_academy uuid := current_setting('cap.academy')::uuid;
  v_b1 uuid := current_setting('cap.b1')::uuid;
  v_b3 uuid := current_setting('cap.b3')::uuid;
  v_s1 uuid := current_setting('cap.s1')::uuid;
  v_caught boolean := false;
begin
  -- Own batch (B1): attendance + performance allowed.
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b1, v_s1, current_date, 'present', 'manual');
    insert into public.performance_assessments
      (academy_id, student_id, batch_id, assessment_date, overall_score)
    values (v_academy, v_s1, v_b1, current_date, 8.0);
  exception when others then
    raise exception 'FAIL: coach could not write to own batch: %', SQLERRM;
  end;

  -- Batch the coach does NOT own (B3, center C2): attendance denied.
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b3, v_s1, current_date + 1, 'present', 'manual');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: coach marked attendance on a batch they do not own';
  end if;
  raise notice 'PASS: coach — own batch read/write, other batch blocked';
end $$;

-- ---------- C3: center_admin — students in own center only ------------------

set local request.jwt.claim.sub = '00000000-0e00-0000-0000-000000000003';  -- ca1 (C1)

do $$
declare
  v_academy uuid := current_setting('cap.academy')::uuid;
  v_c1 uuid := current_setting('cap.c1')::uuid;
  v_c2 uuid := current_setting('cap.c2')::uuid;
  v_caught boolean := false;
begin
  -- Own center → allowed.
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c1, 'New', 'InC1', 'Parent');
  exception when others then
    raise exception 'FAIL: center_admin could not create a student in own center: %', SQLERRM;
  end;

  -- Other center → denied.
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c2, 'New', 'InC2', 'Parent');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: center_admin created a student in a center they do not own';
  end if;
  raise notice 'PASS: center_admin — student writes scoped to own center';
end $$;

-- ---------- C4: head_coach — batches in own center; no student management ---

set local request.jwt.claim.sub = '00000000-0e00-0000-0000-000000000004';  -- hc1 (C1)

do $$
declare
  v_academy uuid := current_setting('cap.academy')::uuid;
  v_c1 uuid := current_setting('cap.c1')::uuid;
  v_c2 uuid := current_setting('cap.c2')::uuid;
  v_caught boolean := false;
begin
  -- Batch in own center → allowed.
  begin
    insert into public.batches (academy_id, center_id, name)
    values (v_academy, v_c1, 'HC new batch C1');
  exception when others then
    raise exception 'FAIL: head_coach could not create a batch in own center: %', SQLERRM;
  end;

  -- Batch in other center → denied.
  begin
    insert into public.batches (academy_id, center_id, name)
    values (v_academy, v_c2, 'HC sneaky batch C2');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: head_coach created a batch in a center they do not manage';
  end if;

  -- Students are NOT a head_coach capability.
  v_caught := false;
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c1, 'HC', 'Student', 'Parent');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: head_coach created a student (should be admin/center_admin only)';
  end if;
  raise notice 'PASS: head_coach — batch writes scoped to center, no student management';
end $$;

-- ---------- C5: coach — cannot manage students or batches -------------------

set local request.jwt.claim.sub = '00000000-0e00-0000-0000-000000000005';  -- co1

do $$
declare
  v_academy uuid := current_setting('cap.academy')::uuid;
  v_c1 uuid := current_setting('cap.c1')::uuid;
  v_caught boolean := false;
begin
  begin
    insert into public.batches (academy_id, center_id, name)
    values (v_academy, v_c1, 'Coach sneaky batch');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: coach created a batch';
  end if;

  v_caught := false;
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c1, 'Coach', 'Student', 'Parent');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: coach created a student';
  end if;
  raise notice 'PASS: coach — cannot manage batches or students';
end $$;

-- ---------- Reset and roll back ---------------------------------------------

reset role;
rollback;

\echo 'All role-capability tests passed.'
