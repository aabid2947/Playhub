-- ============================================================================
-- Trial-quota regression test (20260629000000_trial_quota_limits.sql).
--
-- Asserts the free-trial usage caps:
--   • students       → 5 max on trial, 6th blocked; unlimited when active
--   • coach records  → 2 max on trial, 3rd blocked
--   • sports         → 1 distinct on trial (same sport at 2nd center OK,
--                      a 2nd distinct sport blocked); academy_sports 1 max
--   • staff logins   → trial_role_quota_ok(head_coach) flips to false after 1
--
-- Same harness as rls_subscription_enforcement.sql: impersonate via
-- request.jwt.claim.sub, run in a transaction, roll back. Any 'FAIL' aborts.
-- Inserts use complete, valid column sets so the only possible block is RLS.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

-- ---------- Setup (superuser; RLS bypassed) ---------------------------------
do $$
declare
  v_otrial constant uuid := '00000000-0f10-0000-0000-000000000001'; -- owner, trial
  v_oact   constant uuid := '00000000-0f10-0000-0000-000000000002'; -- owner, active
  v_hc     constant uuid := '00000000-0f10-0000-0000-000000000003'; -- a head_coach login
  v_a_trial uuid;
  v_a_act   uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_c_act uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_otrial, '00000000-0000-0000-0000-000000000000', 'tq-ot@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_oact,   '00000000-0000-0000-0000-000000000000', 'tq-oa@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_hc,     '00000000-0000-0000-0000-000000000000', 'tq-hc@x.invalid', 'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id, subscription_status, trial_ends_at)
  values ('TQ Trial Academy', v_otrial, 'trial', now() + interval '7 days')
  returning id into v_a_trial;
  insert into public.academies (name, owner_id, subscription_status, trial_ends_at)
  values ('TQ Active Academy', v_oact, 'active', now() + interval '30 days')
  returning id into v_a_act;

  insert into public.centers (academy_id, name) values (v_a_trial, 'TQ-C1') returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_a_trial, 'TQ-C2') returning id into v_c2;
  insert into public.centers (academy_id, name) values (v_a_act,   'TQ-CA') returning id into v_c_act;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_otrial, 'academy_owner', v_a_trial, null, 'Own', 'Trial',  'tq-ot@x.invalid'),
    (v_oact,   'academy_owner', v_a_act,   null, 'Own', 'Active', 'tq-oa@x.invalid'),
    (v_hc,     'head_coach',    v_a_trial, v_c1, 'Head','Coach',  'tq-hc@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  perform set_config('tq.a_trial', v_a_trial::text, true);
  perform set_config('tq.a_act',   v_a_act::text,   true);
  perform set_config('tq.c1',      v_c1::text,      true);
  perform set_config('tq.c2',      v_c2::text,      true);
  perform set_config('tq.c_act',   v_c_act::text,   true);
end $$;

set local role authenticated;

-- ---------- students: 5 allowed, 6th blocked (trial) ------------------------
set local request.jwt.claim.sub = '00000000-0f10-0000-0000-000000000001';  -- trial owner
do $$
declare
  v_a uuid := current_setting('tq.a_trial')::uuid;
  v_c uuid := current_setting('tq.c1')::uuid;
  v_caught boolean := false;
  i int;
begin
  for i in 1..5 loop
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_a, v_c, 'S'||i, 'Trial', 'Parent');
  end loop;
  raise notice 'PASS: trial academy created 5 students';

  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_a, v_c, 'S6', 'Trial', 'Parent');
  exception when others then v_caught := true; end;
  if not v_caught then raise exception 'FAIL: trial academy created a 6th student'; end if;
  raise notice 'PASS: trial academy — 6th student blocked';
end $$;

-- ---------- coaches: 2 allowed, 3rd blocked (trial) -------------------------
do $$
declare
  v_a uuid := current_setting('tq.a_trial')::uuid;
  v_c uuid := current_setting('tq.c1')::uuid;
  v_caught boolean := false;
begin
  insert into public.coaches (academy_id, center_id, first_name, last_name) values (v_a, v_c, 'C1', 'Trial');
  insert into public.coaches (academy_id, center_id, first_name, last_name) values (v_a, v_c, 'C2', 'Trial');
  raise notice 'PASS: trial academy created 2 coach records';

  begin
    insert into public.coaches (academy_id, center_id, first_name, last_name) values (v_a, v_c, 'C3', 'Trial');
  exception when others then v_caught := true; end;
  if not v_caught then raise exception 'FAIL: trial academy created a 3rd coach record'; end if;
  raise notice 'PASS: trial academy — 3rd coach record blocked';
end $$;

-- ---------- sports: 1 distinct; same sport @2nd center OK; 2nd distinct blocked
do $$
declare
  v_a uuid := current_setting('tq.a_trial')::uuid;
  v_c1 uuid := current_setting('tq.c1')::uuid;
  v_c2 uuid := current_setting('tq.c2')::uuid;
  v_sport_a uuid := (select id from public.sports where code = 'cricket'  and academy_id is null);
  v_sport_b uuid := (select id from public.sports where code = 'football' and academy_id is null);
  v_caught boolean := false;
begin
  insert into public.center_sports (academy_id, center_id, sport_id) values (v_a, v_c1, v_sport_a);
  raise notice 'PASS: trial academy enabled its 1 sport';

  -- same sport at a different center is fine (still 1 distinct sport)
  insert into public.center_sports (academy_id, center_id, sport_id) values (v_a, v_c2, v_sport_a);
  raise notice 'PASS: trial academy enabled the SAME sport at a 2nd center';

  -- a different sport is the 2nd distinct → blocked
  begin
    insert into public.center_sports (academy_id, center_id, sport_id) values (v_a, v_c1, v_sport_b);
  exception when others then v_caught := true; end;
  if not v_caught then raise exception 'FAIL: trial academy enabled a 2nd distinct sport'; end if;
  raise notice 'PASS: trial academy — 2nd distinct sport blocked';

  -- academy_sports: 1 allowed, 2nd blocked (only where the table exists)
  if to_regclass('public.academy_sports') is not null then
    insert into public.academy_sports (academy_id, sport_id) values (v_a, v_sport_a);
    v_caught := false;
    begin
      insert into public.academy_sports (academy_id, sport_id) values (v_a, v_sport_b);
    exception when others then v_caught := true; end;
    if not v_caught then raise exception 'FAIL: trial academy added a 2nd academy_sport'; end if;
    raise notice 'PASS: trial academy — 2nd academy_sport blocked';
  else
    raise notice 'SKIP: academy_sports table absent — center_sports cap covers sports';
  end if;
end $$;

-- ---------- staff logins: trial_role_quota_ok flips after 1 -----------------
-- (one head_coach already seeded in setup)
do $$ begin
  if public.trial_role_quota_ok('head_coach') then
    raise exception 'FAIL: head_coach quota still open after 1 head_coach exists';
  end if;
  raise notice 'PASS: trial — head_coach login quota exhausted at 1';
  if not public.trial_role_quota_ok('coach') then
    raise exception 'FAIL: coach quota wrongly closed (0 coaches exist)';
  end if;
  raise notice 'PASS: trial — coach login still available (none yet)';
end $$;

-- ---------- active academy: caps LIFTED (6+ students OK) --------------------
set local request.jwt.claim.sub = '00000000-0f10-0000-0000-000000000002';  -- active owner
do $$
declare
  v_a uuid := current_setting('tq.a_act')::uuid;
  v_c uuid := current_setting('tq.c_act')::uuid;
  i int;
begin
  for i in 1..6 loop
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_a, v_c, 'A'||i, 'Active', 'Parent');
  end loop;
  raise notice 'PASS: active academy created 6 students (no trial cap)';

  if public.academy_on_trial() then
    raise exception 'FAIL: active academy reported as on-trial';
  end if;
  raise notice 'PASS: active academy — academy_on_trial() is false';
end $$;

do $$ begin raise notice 'All trial-quota tests passed.'; end $$;

rollback;
