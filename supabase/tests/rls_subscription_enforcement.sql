-- ============================================================================
-- Subscription-enforcement regression test.
--
-- Asserts academy_writes_allowed() + the gated write policies:
--   • active            → writes allowed
--   • trial (not expired) → writes allowed
--   • trial (expired)    → writes BLOCKED (live trial_ends_at check, no cron lag)
--   • suspended          → writes BLOCKED, but READS still work
--   • super_admin        → writes allowed even into a suspended academy
--
-- Same harness as rls_capabilities.sql: impersonate via request.jwt.claim.sub,
-- runs in a transaction and rolls back. Any 'FAIL' aborts.
--
-- NOTE: every "denied" insert uses a COMPLETE, valid column set, so the only
-- possible cause of failure is RLS — a missing NOT NULL column would make a
-- deny-assertion pass spuriously.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

-- ---------- Setup (superuser; RLS bypassed) ---------------------------------
do $$
declare
  v_su   constant uuid := '00000000-0f00-0000-0000-000000000001'; -- super_admin
  v_oa   constant uuid := '00000000-0f00-0000-0000-000000000002'; -- owner, active
  v_os   constant uuid := '00000000-0f00-0000-0000-000000000003'; -- owner, suspended
  v_otx  constant uuid := '00000000-0f00-0000-0000-000000000004'; -- owner, trial expired
  v_oto  constant uuid := '00000000-0f00-0000-0000-000000000005'; -- owner, trial ok
  v_a_active uuid;
  v_a_susp   uuid;
  v_a_trialx uuid;
  v_a_trialok uuid;
  v_c_active uuid;
  v_c_susp   uuid;
  v_c_trialx uuid;
  v_c_trialok uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_su,  '00000000-0000-0000-0000-000000000000', 'sub-su@x.invalid',  'authenticated', 'authenticated', now(), now(), now()),
    (v_oa,  '00000000-0000-0000-0000-000000000000', 'sub-oa@x.invalid',  'authenticated', 'authenticated', now(), now(), now()),
    (v_os,  '00000000-0000-0000-0000-000000000000', 'sub-os@x.invalid',  'authenticated', 'authenticated', now(), now(), now()),
    (v_otx, '00000000-0000-0000-0000-000000000000', 'sub-otx@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_oto, '00000000-0000-0000-0000-000000000000', 'sub-oto@x.invalid', 'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id, subscription_status, trial_ends_at)
  values ('Active Academy', v_oa, 'active', now() + interval '14 days')
  returning id into v_a_active;
  insert into public.academies (name, owner_id, subscription_status, trial_ends_at)
  values ('Suspended Academy', v_os, 'suspended', now() - interval '30 days')
  returning id into v_a_susp;
  insert into public.academies (name, owner_id, subscription_status, trial_ends_at)
  values ('Trial Expired Academy', v_otx, 'trial', now() - interval '1 day')
  returning id into v_a_trialx;
  insert into public.academies (name, owner_id, subscription_status, trial_ends_at)
  values ('Trial OK Academy', v_oto, 'trial', now() + interval '7 days')
  returning id into v_a_trialok;

  insert into public.centers (academy_id, name) values (v_a_active, 'CA') returning id into v_c_active;
  insert into public.centers (academy_id, name) values (v_a_susp,   'CS') returning id into v_c_susp;
  insert into public.centers (academy_id, name) values (v_a_trialx, 'CX') returning id into v_c_trialx;
  insert into public.centers (academy_id, name) values (v_a_trialok,'CO') returning id into v_c_trialok;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_su,  'super_admin',   null,       null,        'Super', 'Admin', 'sub-su@x.invalid'),
    (v_oa,  'academy_owner', v_a_active, null,        'Own',   'Active','sub-oa@x.invalid'),
    (v_os,  'academy_owner', v_a_susp,   null,        'Own',   'Susp',  'sub-os@x.invalid'),
    (v_otx, 'academy_owner', v_a_trialx, null,        'Own',   'TrialX','sub-otx@x.invalid'),
    (v_oto, 'academy_owner', v_a_trialok,null,        'Own',   'TrialO','sub-oto@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id,
        center_id = excluded.center_id;

  -- A student in the suspended academy, for the read-still-works check.
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_a_susp, v_c_susp, 'Existing', 'Student', 'Parent');

  perform set_config('sub.a_active', v_a_active::text, true);
  perform set_config('sub.a_susp',   v_a_susp::text,   true);
  perform set_config('sub.c_active', v_c_active::text, true);
  perform set_config('sub.c_susp',   v_c_susp::text,   true);
  perform set_config('sub.c_trialx', v_c_trialx::text, true);
  perform set_config('sub.c_trialok',v_c_trialok::text,true);
end $$;

-- ---------- academy_writes_allowed() per scenario ---------------------------
set local role authenticated;

set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000002';  -- active
do $$ begin
  if not public.academy_writes_allowed() then
    raise exception 'FAIL: active academy not write-allowed';
  end if;
  raise notice 'PASS: active → writes allowed';
end $$;

set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000005';  -- trial ok
do $$ begin
  if not public.academy_writes_allowed() then
    raise exception 'FAIL: non-expired trial not write-allowed';
  end if;
  raise notice 'PASS: trial (not expired) → writes allowed';
end $$;

set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000004';  -- trial expired
do $$ begin
  if public.academy_writes_allowed() then
    raise exception 'FAIL: expired trial is still write-allowed';
  end if;
  raise notice 'PASS: trial (expired) → writes blocked';
end $$;

set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000003';  -- suspended
do $$ begin
  if public.academy_writes_allowed() then
    raise exception 'FAIL: suspended academy is still write-allowed';
  end if;
  raise notice 'PASS: suspended → writes blocked (helper)';
end $$;

set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000001';  -- super_admin
do $$ begin
  if not public.academy_writes_allowed() then
    raise exception 'FAIL: super_admin not write-allowed';
  end if;
  raise notice 'PASS: super_admin → writes allowed';
end $$;

-- ---------- End-to-end: active owner CAN create a student -------------------
set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000002';  -- active owner
do $$
declare
  v_a uuid := current_setting('sub.a_active')::uuid;
  v_c uuid := current_setting('sub.c_active')::uuid;
begin
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_a, v_c, 'New', 'Active', 'Parent');
  exception when others then
    raise exception 'FAIL: active owner blocked from creating a student: %', SQLERRM;
  end;
  raise notice 'PASS: active owner created a student';
end $$;

-- ---------- End-to-end: suspended owner CANNOT write, CAN read --------------
set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000003';  -- suspended owner
do $$
declare
  v_a uuid := current_setting('sub.a_susp')::uuid;
  v_c uuid := current_setting('sub.c_susp')::uuid;
  v_caught boolean;
  v_seen int;
begin
  -- student insert denied
  v_caught := false;
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_a, v_c, 'Blocked', 'Student', 'Parent');
  exception when others then v_caught := true; end;
  if not v_caught then raise exception 'FAIL: suspended owner created a student'; end if;

  -- coach insert denied
  v_caught := false;
  begin
    insert into public.coaches (academy_id, center_id, first_name, last_name)
    values (v_a, v_c, 'Blocked', 'Coach');
  exception when others then v_caught := true; end;
  if not v_caught then raise exception 'FAIL: suspended owner created a coach'; end if;

  -- reads still work (the existing student is visible)
  select count(*) into v_seen from public.students where academy_id = v_a;
  if v_seen < 1 then
    raise exception 'FAIL: suspended owner cannot read its own students (% seen)', v_seen;
  end if;

  raise notice 'PASS: suspended owner — writes blocked, reads work';
end $$;

-- ---------- End-to-end: trial-expired owner CANNOT create a student --------
set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000004';  -- trial expired
do $$
declare
  v_a uuid := (select academy_id from public.users where id = auth.uid());
  v_caught boolean := false;
begin
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_a, current_setting('sub.c_trialx')::uuid, 'Blocked', 'Trial', 'Parent');
  exception when others then v_caught := true; end;
  if not v_caught then raise exception 'FAIL: trial-expired owner created a student'; end if;
  raise notice 'PASS: trial-expired owner — student create blocked';
end $$;

-- ---------- End-to-end: super_admin CAN write into a suspended academy ------
set local request.jwt.claim.sub = '00000000-0f00-0000-0000-000000000001';  -- super_admin
do $$
declare
  v_a uuid := current_setting('sub.a_susp')::uuid;
  v_c uuid := current_setting('sub.c_susp')::uuid;
begin
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_a, v_c, 'SA', 'Override', 'Parent');
  exception when others then
    raise exception 'FAIL: super_admin blocked writing into a suspended academy: %', SQLERRM;
  end;
  raise notice 'PASS: super_admin — can write into a suspended academy';
end $$;

do $$ begin raise notice 'All subscription-enforcement tests passed.'; end $$;

rollback;
