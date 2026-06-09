-- ============================================================================
-- head_coach student-read scope: their sport's batches only
-- (20260608000500_head_coach_sport_scoped_students.sql).
--
--   head_coach (C1, cricket) can SELECT a student:
--     • enrolled in a CRICKET batch in C1   → yes
--     • enrolled only in a FOOTBALL batch    → no (not their sport)
--     • not enrolled in any of their batches → no
--   center_admin (C1) still sees all C1 students (unchanged).
--
-- Same harness as rls_capabilities.sql: transaction + rollback, impersonate via
-- request.jwt.claim.sub. Any 'FAIL' aborts.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner constant uuid := '00000000-0f00-0000-0000-000000000001';
  v_ca1   constant uuid := '00000000-0f00-0000-0000-000000000003';
  v_hc1   constant uuid := '00000000-0f00-0000-0000-000000000004';
  v_academy uuid;
  v_c1 uuid;
  v_coach_hc1 uuid;
  v_cricket uuid;
  v_football uuid;
  v_b_cricket uuid;
  v_b_football uuid;
  v_s_cricket uuid;
  v_s_football uuid;
  v_s_none uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'hs-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'hs-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_hc1,   '00000000-0000-0000-0000-000000000000', 'hs-hc1@x.invalid',   'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id)
  values ('HC-students Academy', v_owner) returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1')
  returning id into v_c1;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O',  'hs-owner@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'Center', 'A', 'hs-ca1@x.invalid'),
    (v_hc1,   'head_coach',    v_academy, v_c1, 'Head', 'C',   'hs-hc1@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  select id into v_cricket  from public.sports where code = 'cricket';
  select id into v_football from public.sports where code = 'football';

  -- head_coach hc1 owns cricket only.
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_hc1, 'Head', 'C') returning id into v_coach_hc1;
  insert into public.coach_sports (academy_id, coach_id, sport_id)
  values (v_academy, v_coach_hc1, v_cricket);

  insert into public.batches (academy_id, center_id, sport_id, name)
  values (v_academy, v_c1, v_cricket, 'Cricket B') returning id into v_b_cricket;
  insert into public.batches (academy_id, center_id, sport_id, name)
  values (v_academy, v_c1, v_football, 'Football B') returning id into v_b_football;

  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Cric', 'Kid', 'P') returning id into v_s_cricket;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Foot', 'Kid', 'P') returning id into v_s_football;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'None', 'Kid', 'P') returning id into v_s_none;

  insert into public.batch_enrollments (academy_id, batch_id, student_id, enrollment_status)
  values
    (v_academy, v_b_cricket,  v_s_cricket,  'active'),
    (v_academy, v_b_football, v_s_football, 'active');

  perform set_config('hs.cricket', v_s_cricket::text, true);
  perform set_config('hs.football', v_s_football::text, true);
  perform set_config('hs.none', v_s_none::text, true);
end $$;

set local role authenticated;

-- ---------- head_coach hc1 (C1, cricket) ------------------------------------
set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000004';

do $$
declare
  v_cric uuid := current_setting('hs.cricket')::uuid;
  v_foot uuid := current_setting('hs.football')::uuid;
  v_none uuid := current_setting('hs.none')::uuid;
begin
  if (select count(*) from public.students where id = v_cric) <> 1 then
    raise exception 'FAIL: head_coach cannot see a student in their cricket batch';
  end if;
  if (select count(*) from public.students where id = v_foot) <> 0 then
    raise exception 'FAIL: head_coach can see a football-batch student (not their sport)';
  end if;
  if (select count(*) from public.students where id = v_none) <> 0 then
    raise exception 'FAIL: head_coach can see a student not enrolled in their batches';
  end if;
  raise notice 'PASS: head_coach — sees only their sport-batch students';
end $$;

-- ---------- center_admin ca1 (C1) still sees all C1 students ----------------
set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000003';

do $$
declare
  v_cric uuid := current_setting('hs.cricket')::uuid;
  v_foot uuid := current_setting('hs.football')::uuid;
  v_none uuid := current_setting('hs.none')::uuid;
begin
  if (select count(*) from public.students where id in (v_cric, v_foot, v_none)) <> 3 then
    raise exception 'FAIL: center_admin lost visibility of own-center students';
  end if;
  raise notice 'PASS: center_admin — still sees all own-center students';
end $$;

rollback;
