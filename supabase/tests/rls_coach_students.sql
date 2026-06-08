-- ============================================================================
-- Coach batch-scoped student access regression test
-- (20260608000200_coach_batch_scoped_students.sql).
--
--   coach (owns B1, S1 enrolled; S2 in same center but NOT enrolled):
--     • READ   S1 yes, S2 no
--     • UPDATE S1 yes, S2 no (0 rows, no error)
--     • INSERT a new student → denied
--   center_admin (C1) still reads + can manage both S1 and S2.
--
-- Same harness as rls_capabilities.sql: transaction + rollback, impersonate via
-- request.jwt.claim.sub. Any 'FAIL' aborts.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner constant uuid := '00000000-0c00-0000-0000-000000000001';
  v_ca1   constant uuid := '00000000-0c00-0000-0000-000000000003';
  v_co1   constant uuid := '00000000-0c00-0000-0000-000000000005';
  v_academy uuid;
  v_c1 uuid;
  v_coach_co1 uuid;
  v_b1 uuid;
  v_s1 uuid;  -- enrolled in B1 (coach's batch)
  v_s2 uuid;  -- C1, not enrolled anywhere
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'cs-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'cs-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_co1,   '00000000-0000-0000-0000-000000000000', 'cs-co1@x.invalid',   'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id)
  values ('Coach-students Academy', v_owner) returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1') returning id into v_c1;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O',  'cs-owner@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'Center', 'A', 'cs-ca1@x.invalid'),
    (v_co1,   'coach',         v_academy, v_c1, 'Coach', 'O',  'cs-co1@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_co1, 'Coach', 'O') returning id into v_coach_co1;

  insert into public.batches (academy_id, center_id, coach_id, name)
  values (v_academy, v_c1, v_coach_co1, 'B1') returning id into v_b1;

  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Enrolled', 'S1', 'P1') returning id into v_s1;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Unenrolled', 'S2', 'P2') returning id into v_s2;

  insert into public.batch_enrollments (academy_id, batch_id, student_id, enrollment_status)
  values (v_academy, v_b1, v_s1, 'active');

  perform set_config('cs.s1', v_s1::text, true);
  perform set_config('cs.s2', v_s2::text, true);
  perform set_config('cs.academy', v_academy::text, true);
  perform set_config('cs.c1', v_c1::text, true);
end $$;

set local role authenticated;

-- ---------- coach co1 (owns B1) ---------------------------------------------
set local request.jwt.claim.sub = '00000000-0c00-0000-0000-000000000005';

do $$
declare
  v_s1 uuid := current_setting('cs.s1')::uuid;
  v_s2 uuid := current_setting('cs.s2')::uuid;
  v_academy uuid := current_setting('cs.academy')::uuid;
  v_c1 uuid := current_setting('cs.c1')::uuid;
  v_n integer;
  v_caught boolean;
begin
  -- READ: own batch student visible, the other not.
  if (select count(*) from public.students where id = v_s1) <> 1 then
    raise exception 'FAIL: coach cannot see a student in their own batch';
  end if;
  if (select count(*) from public.students where id = v_s2) <> 0 then
    raise exception 'FAIL: coach can see a student not in any of their batches';
  end if;

  -- UPDATE: own batch student editable.
  update public.students set city = 'Pune' where id = v_s1;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'FAIL: coach could not edit a student in their own batch';
  end if;

  -- UPDATE: non-batch student not editable (0 rows, no error).
  update public.students set city = 'Pune' where id = v_s2;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FAIL: coach edited a student not in their batch';
  end if;

  -- INSERT: coaches no longer onboard.
  v_caught := false;
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c1, 'New', 'ByCoach', 'P');
  exception when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: coach created a student record';
  end if;

  raise notice 'PASS: coach — read+edit own-batch students only, no create';
end $$;

-- ---------- center_admin ca1 (C1) still manages both ------------------------
set local request.jwt.claim.sub = '00000000-0c00-0000-0000-000000000003';

do $$
declare
  v_s1 uuid := current_setting('cs.s1')::uuid;
  v_s2 uuid := current_setting('cs.s2')::uuid;
  v_n integer;
begin
  if (select count(*) from public.students where id in (v_s1, v_s2)) <> 2 then
    raise exception 'FAIL: center_admin lost visibility of own-center students';
  end if;
  update public.students set city = 'Mumbai' where id = v_s2;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'FAIL: center_admin could not edit an own-center student';
  end if;
  raise notice 'PASS: center_admin — still manages all own-center students';
end $$;

rollback;
