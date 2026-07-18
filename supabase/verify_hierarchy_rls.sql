-- ============================================================================
-- PlayHub - backend RLS verification for the hierarchy work.
--
-- Paste-and-run in the Supabase SQL editor AFTER applying the migrations
-- (apply_hierarchy_phases_1_to_5.sql). Covers the 5 new hierarchy tests plus
-- the 2 base tests the hierarchy work changed (rls_capabilities, rls_trainer_media).
--
-- HOW TO READ: completes with NO error = ALL passed (each block raises the
-- moment something is wrong). Stops with 'FAIL: ...' = that assertion failed.
--
-- NON-DESTRUCTIVE: every test runs inside begin;...rollback; (test data is
-- discarded). Prefer a staging/dev project over production anyway.
--
-- (psql meta-commands \set / \echo are stripped so this runs in the editor;
--  the originals under supabase/tests/ are the CI source of truth.)
-- ============================================================================


-- ##########################################################################
-- ## rls_provisioning.sql
-- ##########################################################################

-- ============================================================================
-- Provisioning-ladder regression test.
--
-- Covers 20260607000000_provisioning_ladder.sql + 20260607000100_harden_auth_trigger.sql:
--   A. can_provision_role(target, center) matrix per caller role
--      (rank ceiling + center scope + parent/student = record-managers only).
--   B. public.users write RLS: no upward/lateral promotion, no cross-center
--      poaching; managing the rung below in your own center is allowed.
--   C. handle_new_auth_user no longer trusts client-supplied user_metadata:
--      a self-signup cannot mint a privileged role; app_metadata and the
--      invite path (invited_at) are still honoured.
--
-- Same harness as rls_capabilities.sql: superuser setup, impersonate via
-- request.jwt.claim.sub, run in a transaction and roll back.
-- ============================================================================


begin;

-- ---------- Setup (superuser; RLS bypassed) ---------------------------------

do $$
declare
  v_owner constant uuid := '00000000-0b00-0000-0000-000000000001';
  v_admin constant uuid := '00000000-0b00-0000-0000-000000000002';
  v_ca1   constant uuid := '00000000-0b00-0000-0000-000000000003';
  v_hc1   constant uuid := '00000000-0b00-0000-0000-000000000004';
  v_co1   constant uuid := '00000000-0b00-0000-0000-000000000005';
  v_tr1   constant uuid := '00000000-0b00-0000-0000-000000000006';
  v_academy uuid;
  v_c1 uuid;
  v_c2 uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'prov-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'prov-admin@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'prov-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_hc1,   '00000000-0000-0000-0000-000000000000', 'prov-hc1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_co1,   '00000000-0000-0000-0000-000000000000', 'prov-co1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_tr1,   '00000000-0000-0000-0000-000000000000', 'prov-tr1@x.invalid',   'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id)
  values ('Provisioning Academy', v_owner)
  returning id into v_academy;

  insert into public.centers (academy_id, name) values (v_academy, 'C1')
  returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_academy, 'C2')
  returning id into v_c2;

  -- The trigger created stub rows on the auth inserts above; set the real
  -- roles/centers here (RLS bypassed as superuser).
  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O', 'prov-owner@x.invalid'),
    (v_admin, 'academy_admin', v_academy, null, 'Admin', 'A', 'prov-admin@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'Center', 'Admin1', 'prov-ca1@x.invalid'),
    (v_hc1,   'head_coach',    v_academy, v_c1, 'Head', 'Coach1', 'prov-hc1@x.invalid'),
    (v_co1,   'coach',         v_academy, v_c1, 'Coach', 'One', 'prov-co1@x.invalid'),
    (v_tr1,   'trainer',       v_academy, v_c1, 'Trainer', 'One', 'prov-tr1@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id,
        center_id = excluded.center_id;

  perform set_config('prov.academy', v_academy::text, true);
  perform set_config('prov.c1', v_c1::text, true);
  perform set_config('prov.c2', v_c2::text, true);
  perform set_config('prov.co1', v_co1::text, true);

  raise notice '[prov setup] academy %, centers % %', v_academy, v_c1, v_c2;
end $$;

-- ============================================================================
-- A. can_provision_role matrix.
-- ============================================================================

set local role authenticated;

-- ---- owner: academy-wide, anyone below; never a peer/super_admin -----------
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000001';
do $$
declare
  r record;
  v_c1 uuid := current_setting('prov.c1')::uuid;
  v_c2 uuid := current_setting('prov.c2')::uuid;
begin
  for r in select * from (values
    ('academy_admin'::public.user_role, null::uuid, true),
    ('center_admin'::public.user_role,  v_c1,       true),
    ('coach'::public.user_role,         v_c2,       true),
    ('student'::public.user_role,       v_c1,       true),
    ('academy_owner'::public.user_role, null::uuid, false),  -- peer
    ('super_admin'::public.user_role,   null::uuid, false)
  ) t(target, center, expected) loop
    if public.can_provision_role(r.target, r.center) <> r.expected then
      raise exception 'FAIL: owner can_provision_role(%, %) expected %',
        r.target, r.center, r.expected;
    end if;
  end loop;
  raise notice 'PASS: owner provisioning matrix';
end $$;

-- ---- academy_admin: everything below, never another admin/owner ------------
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000002';
do $$
declare
  r record;
  v_c1 uuid := current_setting('prov.c1')::uuid;
begin
  for r in select * from (values
    ('center_admin'::public.user_role,  v_c1,       true),
    ('head_coach'::public.user_role,    v_c1,       true),
    ('parent'::public.user_role,        v_c1,       true),
    ('academy_admin'::public.user_role, null::uuid, false),  -- peer
    ('academy_owner'::public.user_role, null::uuid, false)
  ) t(target, center, expected) loop
    if public.can_provision_role(r.target, r.center) <> r.expected then
      raise exception 'FAIL: admin can_provision_role(%, %) expected %',
        r.target, r.center, r.expected;
    end if;
  end loop;
  raise notice 'PASS: academy_admin provisioning matrix';
end $$;

-- ---- center_admin (C1): staff + end-users in OWN center only ---------------
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000003';
do $$
declare
  r record;
  v_c1 uuid := current_setting('prov.c1')::uuid;
  v_c2 uuid := current_setting('prov.c2')::uuid;
begin
  for r in select * from (values
    ('head_coach'::public.user_role,    v_c1, true),
    ('coach'::public.user_role,         v_c1, true),
    ('trainer'::public.user_role,       v_c1, true),
    ('parent'::public.user_role,        v_c1, true),
    ('student'::public.user_role,       v_c1, true),
    ('head_coach'::public.user_role,    v_c2, false),  -- other center
    ('parent'::public.user_role,        v_c2, false),  -- other center
    ('center_admin'::public.user_role,  v_c1, false),  -- peer
    ('academy_admin'::public.user_role, v_c1, false)   -- superior
  ) t(target, center, expected) loop
    if public.can_provision_role(r.target, r.center) <> r.expected then
      raise exception 'FAIL: center_admin can_provision_role(%, %) expected %',
        r.target, r.center, r.expected;
    end if;
  end loop;
  raise notice 'PASS: center_admin provisioning matrix';
end $$;

-- ---- head_coach (C1): coach/trainer own center; NOT parent/student ---------
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000004';
do $$
declare
  r record;
  v_c1 uuid := current_setting('prov.c1')::uuid;
  v_c2 uuid := current_setting('prov.c2')::uuid;
begin
  for r in select * from (values
    ('coach'::public.user_role,        v_c1, true),
    ('trainer'::public.user_role,      v_c1, true),
    ('coach'::public.user_role,        v_c2, false),  -- other center
    ('head_coach'::public.user_role,   v_c1, false),  -- peer
    ('center_admin'::public.user_role, v_c1, false),  -- superior
    ('parent'::public.user_role,       v_c1, false),  -- not a record-manager
    ('student'::public.user_role,      v_c1, false)
  ) t(target, center, expected) loop
    if public.can_provision_role(r.target, r.center) <> r.expected then
      raise exception 'FAIL: head_coach can_provision_role(%, %) expected %',
        r.target, r.center, r.expected;
    end if;
  end loop;
  raise notice 'PASS: head_coach provisioning matrix';
end $$;

-- ---- coach (C1): trainer own center only; nothing else ---------------------
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000005';
do $$
declare
  r record;
  v_c1 uuid := current_setting('prov.c1')::uuid;
  v_c2 uuid := current_setting('prov.c2')::uuid;
begin
  for r in select * from (values
    ('trainer'::public.user_role,    v_c1, true),
    ('trainer'::public.user_role,    v_c2, false),  -- other center
    ('coach'::public.user_role,      v_c1, false),  -- peer
    ('head_coach'::public.user_role, v_c1, false),  -- superior
    ('parent'::public.user_role,     v_c1, false),  -- not a record-manager
    ('student'::public.user_role,    v_c1, false)
  ) t(target, center, expected) loop
    if public.can_provision_role(r.target, r.center) <> r.expected then
      raise exception 'FAIL: coach can_provision_role(%, %) expected %',
        r.target, r.center, r.expected;
    end if;
  end loop;
  raise notice 'PASS: coach provisioning matrix';
end $$;

-- ---- trainer: provisions nobody --------------------------------------------
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000006';
do $$
declare
  r record;
  v_c1 uuid := current_setting('prov.c1')::uuid;
begin
  for r in select * from (values
    ('trainer'::public.user_role, v_c1, false),
    ('student'::public.user_role, v_c1, false),
    ('parent'::public.user_role,  v_c1, false),
    ('coach'::public.user_role,   v_c1, false)
  ) t(target, center, expected) loop
    if public.can_provision_role(r.target, r.center) <> r.expected then
      raise exception 'FAIL: trainer can_provision_role(%, %) expected %',
        r.target, r.center, r.expected;
    end if;
  end loop;
  raise notice 'PASS: trainer provisions nobody';
end $$;

-- ============================================================================
-- B. users-table write RLS — no escalation via UPDATE.
-- center_admin (C1) acting on the C1 coach (co1).
-- ============================================================================

set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000003';  -- ca1 (C1)
do $$
declare
  v_co1 uuid := current_setting('prov.co1')::uuid;
  v_c2 uuid := current_setting('prov.c2')::uuid;
  v_caught boolean;
begin
  -- Promote the coach to academy_admin → must be denied (rank ceiling).
  v_caught := false;
  begin
    update public.users set role = 'academy_admin' where id = v_co1;
    if not found then v_caught := true; end if;  -- RLS hid the row → no-op
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: center_admin promoted a coach to academy_admin';
  end if;

  -- Move the coach to another center → must be denied (cross-center poach).
  v_caught := false;
  begin
    update public.users set center_id = v_c2 where id = v_co1;
    if not found then v_caught := true; end if;
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: center_admin moved a coach to another center';
  end if;

  -- Edit a benign field on the rung below in own center → allowed.
  begin
    update public.users set first_name = 'Renamed' where id = v_co1;
  exception when others then
    raise exception 'FAIL: center_admin could not edit own-center coach: %', SQLERRM;
  end;

  raise notice 'PASS: users RLS — no promotion/poaching, own-center edit allowed';
end $$;

-- head_coach cannot promote the coach to center_admin either.
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000004';  -- hc1 (C1)
do $$
declare
  v_co1 uuid := current_setting('prov.co1')::uuid;
  v_caught boolean := false;
begin
  begin
    update public.users set role = 'center_admin' where id = v_co1;
    if not found then v_caught := true; end if;
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: head_coach promoted a coach to center_admin';
  end if;
  raise notice 'PASS: head_coach cannot promote a coach upward';
end $$;

-- ============================================================================
-- C. handle_new_auth_user — self-signup cannot escalate.
-- Run as superuser (auth.users is not client-writable).
-- ============================================================================

reset role;
do $$
declare
  v_academy uuid := current_setting('prov.academy')::uuid;
  v_c1 uuid := current_setting('prov.c1')::uuid;
  v_attacker constant uuid := '00000000-0b00-0000-0000-0000000000a1';
  v_app constant uuid       := '00000000-0b00-0000-0000-0000000000a2';
  v_invited constant uuid   := '00000000-0b00-0000-0000-0000000000a3';
begin
  -- (1) Self-signup with crafted USER metadata, no invited_at, no app_metadata:
  --     privileged fields ignored → plain student, no academy. Names still kept.
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at,
                          raw_user_meta_data)
  values (v_attacker, '00000000-0000-0000-0000-000000000000',
          'prov-attacker@x.invalid', 'authenticated', 'authenticated',
          now(), now(), now(),
          jsonb_build_object('role', 'academy_admin',
                             'academy_id', v_academy::text,
                             'first_name', 'Eve'));
  if (select role from public.users where id = v_attacker) <> 'student' then
    raise exception 'FAIL: self-signup user_metadata role was honoured (escalation!)';
  end if;
  if (select academy_id from public.users where id = v_attacker) is not null then
    raise exception 'FAIL: self-signup attached itself to an academy';
  end if;
  if (select first_name from public.users where id = v_attacker) <> 'Eve' then
    raise exception 'FAIL: non-privileged first_name was dropped';
  end if;

  -- (2) Service-role creation via APP metadata → honoured.
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data)
  values (v_app, '00000000-0000-0000-0000-000000000000',
          'prov-app@x.invalid', 'authenticated', 'authenticated',
          now(), now(), now(),
          jsonb_build_object('role', 'coach',
                             'academy_id', v_academy::text,
                             'center_id', v_c1::text));
  if (select role from public.users where id = v_app) <> 'coach' then
    raise exception 'FAIL: app_metadata role was not honoured';
  end if;
  if (select center_id from public.users where id = v_app) <> v_c1 then
    raise exception 'FAIL: app_metadata center_id was not honoured';
  end if;

  -- (3) Admin invite path (invited_at set) via USER metadata → honoured.
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at,
                          invited_at, raw_user_meta_data)
  values (v_invited, '00000000-0000-0000-0000-000000000000',
          'prov-invited@x.invalid', 'authenticated', 'authenticated',
          now(), now(), now(), now(),
          jsonb_build_object('role', 'trainer', 'academy_id', v_academy::text));
  if (select role from public.users where id = v_invited) <> 'trainer' then
    raise exception 'FAIL: invited user_metadata role was not honoured';
  end if;

  raise notice 'PASS: auth trigger — self-signup blocked, app_metadata + invite honoured';
end $$;

-- ---------- Roll back -------------------------------------------------------

rollback;




-- ##########################################################################
-- ## rls_sport_scope.sql
-- ##########################################################################

-- ============================================================================
-- Phase 2 regression — head_coach sport scope + center_admin sport enablement
-- (20260607000200_head_coach_sport_scope.sql).
--
--   • head_coach (C1, cricket): attendance + performance on a CRICKET batch in
--     C1 = yes; on a FOOTBALL batch in C1 = no (own sport only).
--   • center_admin (C1): enable a sport for C1 = yes; for C2 = no.
--   • head_coach: cannot write center_sports (not an admin-center-scope role).
--
-- Same harness as rls_capabilities.sql.
-- ============================================================================


begin;

do $$
declare
  v_hc   constant uuid := '00000000-0c00-0000-0000-000000000001';
  v_ca   constant uuid := '00000000-0c00-0000-0000-000000000002';
  v_academy uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_coach_hc uuid;
  v_cricket uuid;
  v_football uuid;
  v_b_cricket uuid;
  v_b_football uuid;
  v_student uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_hc, '00000000-0000-0000-0000-000000000000', 'sport-hc@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca, '00000000-0000-0000-0000-000000000000', 'sport-ca@x.invalid', 'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name) values ('Sport Scope Academy') returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1') returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_academy, 'C2') returning id into v_c2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_hc, 'head_coach',   v_academy, v_c1, 'Head', 'Coach', 'sport-hc@x.invalid'),
    (v_ca, 'center_admin', v_academy, v_c1, 'Center', 'Admin', 'sport-ca@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  select id into v_cricket  from public.sports where code = 'cricket';
  select id into v_football from public.sports where code = 'football';

  -- head_coach is linked to a coaches row, qualified for cricket only.
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_hc, 'Head', 'Coach') returning id into v_coach_hc;
  insert into public.coach_sports (academy_id, coach_id, sport_id)
  values (v_academy, v_coach_hc, v_cricket);

  insert into public.batches (academy_id, center_id, sport_id, name)
  values (v_academy, v_c1, v_cricket, 'Cricket B') returning id into v_b_cricket;
  insert into public.batches (academy_id, center_id, sport_id, name)
  values (v_academy, v_c1, v_football, 'Football B') returning id into v_b_football;

  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'Sam', 'C1', 'Parent') returning id into v_student;

  perform set_config('sp.academy', v_academy::text, true);
  perform set_config('sp.c1', v_c1::text, true);
  perform set_config('sp.c2', v_c2::text, true);
  perform set_config('sp.cricket', v_cricket::text, true);
  perform set_config('sp.football', v_football::text, true);
  perform set_config('sp.b_cricket', v_b_cricket::text, true);
  perform set_config('sp.b_football', v_b_football::text, true);
  perform set_config('sp.student', v_student::text, true);
end $$;

-- ---------- head_coach: attendance + performance only in own sport ----------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0c00-0000-0000-000000000001';  -- hc

do $$
declare
  v_academy uuid := current_setting('sp.academy')::uuid;
  v_b_cricket uuid := current_setting('sp.b_cricket')::uuid;
  v_b_football uuid := current_setting('sp.b_football')::uuid;
  v_student uuid := current_setting('sp.student')::uuid;
  v_caught boolean := false;
begin
  -- Own sport (cricket): attendance + performance allowed.
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b_cricket, v_student, current_date, 'present', 'manual');
    insert into public.performance_assessments
      (academy_id, student_id, batch_id, assessment_date, overall_score)
    values (v_academy, v_student, v_b_cricket, current_date, 8.0);
  exception when others then
    raise exception 'FAIL: head_coach blocked on own-sport batch: %', SQLERRM;
  end;

  -- Other sport (football) in same center: attendance denied.
  v_caught := false;
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b_football, v_student, current_date + 1, 'present', 'manual');
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: head_coach marked attendance on a sport they do not coach';
  end if;

  -- Other sport (football): performance denied.
  v_caught := false;
  begin
    insert into public.performance_assessments
      (academy_id, student_id, batch_id, assessment_date, overall_score)
    values (v_academy, v_student, v_b_football, current_date, 7.0);
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: head_coach recorded performance on a sport they do not coach';
  end if;

  -- head_coach cannot enable a sport for the center (not an admin-scope role).
  v_caught := false;
  begin
    insert into public.center_sports (academy_id, center_id, sport_id)
    values (v_academy, current_setting('sp.c1')::uuid, current_setting('sp.football')::uuid);
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: head_coach enabled a center sport';
  end if;

  raise notice 'PASS: head_coach — own-sport only, no center_sports writes';
end $$;

-- ---------- center_admin: enable sports for OWN center only -----------------

set local request.jwt.claim.sub = '00000000-0c00-0000-0000-000000000002';  -- ca (C1)

do $$
declare
  v_academy uuid := current_setting('sp.academy')::uuid;
  v_c1 uuid := current_setting('sp.c1')::uuid;
  v_c2 uuid := current_setting('sp.c2')::uuid;
  v_football uuid := current_setting('sp.football')::uuid;
  v_cricket uuid := current_setting('sp.cricket')::uuid;
  v_caught boolean := false;
begin
  -- Own center → allowed.
  begin
    insert into public.center_sports (academy_id, center_id, sport_id)
    values (v_academy, v_c1, v_football);
  exception when others then
    raise exception 'FAIL: center_admin could not enable a sport for own center: %', SQLERRM;
  end;

  -- Other center → denied.
  v_caught := false;
  begin
    insert into public.center_sports (academy_id, center_id, sport_id)
    values (v_academy, v_c2, v_cricket);
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: center_admin enabled a sport for a center they do not manage';
  end if;

  raise notice 'PASS: center_admin — center_sports scoped to own center';
end $$;

reset role;
rollback;




-- ##########################################################################
-- ## rls_batch_staff.sql
-- ##########################################################################

-- ============================================================================
-- Phase 3 regression — batch_staff, trainer→student scope, coach enrollment
-- (20260607000300_batch_staff_trainer_scope.sql).
--
-- Setup: one academy, center C1.
--   batch B  — coached by `co`; trainer `tr` assigned via batch_staff; student s.
--   batch B2 — coached by `co2`; student s2; `tr` is NOT staff here.
--
-- Asserts:
--   • trainer: student_assigned_to_me(s)=yes, (s2)=no; attendance + performance
--     on B = yes, on B2 = no; cannot enrol students.
--   • coach: can enrol into own batch B, not B2; can add staff to B, not B2.
-- ============================================================================


begin;

do $$
declare
  v_co  constant uuid := '00000000-0d00-0000-0000-000000000001';
  v_tr  constant uuid := '00000000-0d00-0000-0000-000000000002';
  v_co2 constant uuid := '00000000-0d00-0000-0000-000000000003';
  v_academy uuid;
  v_c1 uuid;
  v_coach_co uuid;
  v_coach_co2 uuid;
  v_b uuid;
  v_b2 uuid;
  v_s uuid;
  v_s2 uuid;
  v_s3 uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_co,  '00000000-0000-0000-0000-000000000000', 'bs-co@x.invalid',  'authenticated', 'authenticated', now(), now(), now()),
    (v_tr,  '00000000-0000-0000-0000-000000000000', 'bs-tr@x.invalid',  'authenticated', 'authenticated', now(), now(), now()),
    (v_co2, '00000000-0000-0000-0000-000000000000', 'bs-co2@x.invalid', 'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name) values ('Batch Staff Academy') returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1') returning id into v_c1;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_co,  'coach',   v_academy, v_c1, 'Co',  'One', 'bs-co@x.invalid'),
    (v_tr,  'trainer', v_academy, v_c1, 'Tr',  'One', 'bs-tr@x.invalid'),
    (v_co2, 'coach',   v_academy, v_c1, 'Co',  'Two', 'bs-co2@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_co, 'Co', 'One') returning id into v_coach_co;
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_co2, 'Co', 'Two') returning id into v_coach_co2;

  insert into public.batches (academy_id, center_id, coach_id, name)
  values (v_academy, v_c1, v_coach_co, 'B') returning id into v_b;
  insert into public.batches (academy_id, center_id, coach_id, name)
  values (v_academy, v_c1, v_coach_co2, 'B2') returning id into v_b2;

  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'S', 'One', 'P') returning id into v_s;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'S', 'Two', 'P') returning id into v_s2;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_c1, 'S', 'Three', 'P') returning id into v_s3;

  insert into public.batch_enrollments (academy_id, batch_id, student_id, enrollment_status)
  values (v_academy, v_b, v_s, 'active'),
         (v_academy, v_b2, v_s2, 'active');

  -- tr is an assigned trainer on batch B (not B2).
  insert into public.batch_staff (academy_id, batch_id, user_id, role)
  values (v_academy, v_b, v_tr, 'trainer');

  perform set_config('bs.academy', v_academy::text, true);
  perform set_config('bs.b', v_b::text, true);
  perform set_config('bs.b2', v_b2::text, true);
  perform set_config('bs.s', v_s::text, true);
  perform set_config('bs.s2', v_s2::text, true);
  perform set_config('bs.s3', v_s3::text, true);
  perform set_config('bs.co2user', v_co2::text, true);
end $$;

-- ---------- trainer: scoped to students in batches they staff ---------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0d00-0000-0000-000000000002';  -- tr

do $$
declare
  v_academy uuid := current_setting('bs.academy')::uuid;
  v_b uuid := current_setting('bs.b')::uuid;
  v_b2 uuid := current_setting('bs.b2')::uuid;
  v_s uuid := current_setting('bs.s')::uuid;
  v_s2 uuid := current_setting('bs.s2')::uuid;
  v_s3 uuid := current_setting('bs.s3')::uuid;
  v_caught boolean := false;
begin
  -- "My students" resolves through batch_staff.
  if not public.student_assigned_to_me(v_s) then
    raise exception 'FAIL: trainer should be assigned to student s (enrolled in their batch)';
  end if;
  if public.student_assigned_to_me(v_s2) then
    raise exception 'FAIL: trainer is NOT assigned to s2 (other batch)';
  end if;

  -- Attendance + performance on the staffed batch B → allowed.
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b, v_s, current_date, 'present', 'manual');
    insert into public.performance_assessments
      (academy_id, student_id, batch_id, assessment_date, overall_score)
    values (v_academy, v_s, v_b, current_date, 7.5);
  exception when others then
    raise exception 'FAIL: trainer blocked on staffed batch: %', SQLERRM;
  end;

  -- Attendance on a batch they don't staff (B2) → denied.
  v_caught := false;
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b2, v_s2, current_date, 'present', 'manual');
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: trainer marked attendance on a batch they do not staff';
  end if;

  -- Trainers cannot enrol students (not a coach/management role).
  v_caught := false;
  begin
    insert into public.batch_enrollments (academy_id, batch_id, student_id, enrollment_status)
    values (v_academy, v_b, v_s3, 'active');
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: trainer enrolled a student';
  end if;

  raise notice 'PASS: trainer — scoped to staffed-batch students; no enrolment';
end $$;

-- ---------- coach: enrol into own batch; staff own batch --------------------

set local request.jwt.claim.sub = '00000000-0d00-0000-0000-000000000001';  -- co

do $$
declare
  v_academy uuid := current_setting('bs.academy')::uuid;
  v_b uuid := current_setting('bs.b')::uuid;
  v_b2 uuid := current_setting('bs.b2')::uuid;
  v_s3 uuid := current_setting('bs.s3')::uuid;
  v_co2 uuid := current_setting('bs.co2user')::uuid;
  v_caught boolean := false;
begin
  -- Enrol a student into OWN batch B → allowed.
  begin
    insert into public.batch_enrollments (academy_id, batch_id, student_id, enrollment_status)
    values (v_academy, v_b, v_s3, 'active');
  exception when others then
    raise exception 'FAIL: coach could not enrol into own batch: %', SQLERRM;
  end;

  -- Enrol into a batch they do NOT coach (B2) → denied.
  v_caught := false;
  begin
    insert into public.batch_enrollments (academy_id, batch_id, student_id, enrollment_status)
    values (v_academy, v_b2, v_s3, 'active');
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: coach enrolled into a batch they do not coach';
  end if;

  -- Add staff to OWN batch B → allowed.
  begin
    insert into public.batch_staff (academy_id, batch_id, user_id, role)
    values (v_academy, v_b, v_co2, 'assistant_coach');
  exception when others then
    raise exception 'FAIL: coach could not add staff to own batch: %', SQLERRM;
  end;

  -- Add staff to a batch they do NOT coach (B2) → denied.
  v_caught := false;
  begin
    insert into public.batch_staff (academy_id, batch_id, user_id, role)
    values (v_academy, v_b2, v_co2, 'assistant_coach');
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: coach added staff to a batch they do not coach';
  end if;

  raise notice 'PASS: coach — enrol + staff own batch only';
end $$;

reset role;
rollback;




-- ##########################################################################
-- ## rls_finance_scope.sql
-- ##########################################################################

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




-- ##########################################################################
-- ## rls_center_read_isolation.sql
-- ##########################################################################

-- ============================================================================
-- Phase 5 regression — center_admin READ isolation on the secondary lists
-- (20260607000500_center_read_isolation.sql).
--
-- One academy, centers C1/C2. center_admin ca1 in C1; a coach cc in C1 (to
-- prove non-center_admins are unaffected). One of each entity per center.
--
-- Asserts:
--   • center_admin (C1) sees own-center coaches/leads/items/events/batch_staff,
--     NOT the C2 ones.
--   • coach (non-center_admin) still sees coaches academy-wide (short-circuit).
--   • announcements: non-admin sees only ones delivered to them; admin sees all.
-- ============================================================================


begin;

do $$
declare
  v_owner constant uuid := '00000000-1100-0000-0000-000000000001';
  v_ca1   constant uuid := '00000000-1100-0000-0000-000000000002';
  v_cc    constant uuid := '00000000-1100-0000-0000-000000000003';
  v_academy uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_coach1 uuid; v_coach2 uuid;
  v_lead1 uuid;  v_lead2 uuid;
  v_item1 uuid;  v_item2 uuid;
  v_event1 uuid; v_event2 uuid;
  v_b1 uuid;     v_b2 uuid;
  v_annA uuid;   v_annB uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'cri-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'cri-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_cc,    '00000000-0000-0000-0000-000000000000', 'cri-cc@x.invalid',    'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id) values ('Read-Iso Academy', v_owner)
  returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1') returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_academy, 'C2') returning id into v_c2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O', 'cri-owner@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'CA', '1', 'cri-ca1@x.invalid'),
    (v_cc,    'coach',         v_academy, v_c1, 'Co', 'X', 'cri-cc@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c1, 'Coach', 'C1') returning id into v_coach1;
  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c2, 'Coach', 'C2') returning id into v_coach2;

  insert into public.leads (academy_id, first_name, phone, preferred_center_id)
  values (v_academy, 'Lead', '+919000000001', v_c1) returning id into v_lead1;
  insert into public.leads (academy_id, first_name, phone, preferred_center_id)
  values (v_academy, 'Lead', '+919000000002', v_c2) returning id into v_lead2;

  insert into public.inventory_items (academy_id, center_id, name)
  values (v_academy, v_c1, 'Item C1') returning id into v_item1;
  insert into public.inventory_items (academy_id, center_id, name)
  values (v_academy, v_c2, 'Item C2') returning id into v_item2;

  insert into public.events (academy_id, center_id, title, starts_at, status)
  values (v_academy, v_c1, 'Event C1', now(), 'published') returning id into v_event1;
  insert into public.events (academy_id, center_id, title, starts_at, status)
  values (v_academy, v_c2, 'Event C2', now(), 'published') returning id into v_event2;

  insert into public.batches (academy_id, center_id, name)
  values (v_academy, v_c1, 'B C1') returning id into v_b1;
  insert into public.batches (academy_id, center_id, name)
  values (v_academy, v_c2, 'B C2') returning id into v_b2;

  insert into public.batch_staff (academy_id, batch_id, user_id, role)
  values (v_academy, v_b1, v_cc, 'trainer'),
         (v_academy, v_b2, v_cc, 'trainer');

  insert into public.announcements (academy_id, subject, body, created_by)
  values (v_academy, 'A', 'delivered to ca1', v_owner) returning id into v_annA;
  insert into public.announcements (academy_id, subject, body, created_by)
  values (v_academy, 'B', 'not delivered to ca1', v_owner) returning id into v_annB;
  insert into public.announcement_recipients (academy_id, announcement_id, user_id)
  values (v_academy, v_annA, v_ca1);

  perform set_config('cri.academy', v_academy::text, true);
  perform set_config('cri.coach1', v_coach1::text, true);
  perform set_config('cri.coach2', v_coach2::text, true);
  perform set_config('cri.lead1', v_lead1::text, true);
  perform set_config('cri.lead2', v_lead2::text, true);
  perform set_config('cri.item1', v_item1::text, true);
  perform set_config('cri.item2', v_item2::text, true);
  perform set_config('cri.event1', v_event1::text, true);
  perform set_config('cri.event2', v_event2::text, true);
  perform set_config('cri.b1', v_b1::text, true);
  perform set_config('cri.b2', v_b2::text, true);
  perform set_config('cri.annA', v_annA::text, true);
  perform set_config('cri.annB', v_annB::text, true);
end $$;

-- ---------- center_admin (C1): own-center secondary lists only --------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-1100-0000-0000-000000000002';  -- ca1

do $$
declare
  v_ok int; v_bad int;
begin
  select count(*) into v_ok  from public.coaches where id = current_setting('cri.coach1')::uuid;
  select count(*) into v_bad from public.coaches where id = current_setting('cri.coach2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: coaches not center-scoped (own=%, other=%)', v_ok, v_bad; end if;

  select count(*) into v_ok  from public.leads where id = current_setting('cri.lead1')::uuid;
  select count(*) into v_bad from public.leads where id = current_setting('cri.lead2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: leads not center-scoped'; end if;

  select count(*) into v_ok  from public.inventory_items where id = current_setting('cri.item1')::uuid;
  select count(*) into v_bad from public.inventory_items where id = current_setting('cri.item2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: inventory_items not center-scoped'; end if;

  select count(*) into v_ok  from public.events where id = current_setting('cri.event1')::uuid;
  select count(*) into v_bad from public.events where id = current_setting('cri.event2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: events not center-scoped'; end if;

  select count(*) into v_ok  from public.batch_staff where batch_id = current_setting('cri.b1')::uuid;
  select count(*) into v_bad from public.batch_staff where batch_id = current_setting('cri.b2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: batch_staff not center-scoped'; end if;

  -- Announcements: only the one delivered to ca1.
  select count(*) into v_ok  from public.announcements where id = current_setting('cri.annA')::uuid;
  select count(*) into v_bad from public.announcements where id = current_setting('cri.annB')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: announcements not delivery-scoped (A=%, B=%)', v_ok, v_bad; end if;

  raise notice 'PASS: center_admin — secondary lists + announcements scoped';
end $$;

-- ---------- coach (non-center_admin): coaches still academy-wide ------------

set local request.jwt.claim.sub = '00000000-1100-0000-0000-000000000003';  -- cc

do $$
declare
  v_c1 int; v_c2 int;
begin
  select count(*) into v_c1 from public.coaches where id = current_setting('cri.coach1')::uuid;
  select count(*) into v_c2 from public.coaches where id = current_setting('cri.coach2')::uuid;
  if v_c1 <> 1 or v_c2 <> 1 then
    raise exception 'FAIL: coach should see both coaches academy-wide (c1=%, c2=%)', v_c1, v_c2;
  end if;
  raise notice 'PASS: non-center_admin unaffected (academy-wide coaches)';
end $$;

-- ---------- owner: sees all + all announcements -----------------------------

set local request.jwt.claim.sub = '00000000-1100-0000-0000-000000000001';  -- owner

do $$
declare
  v_ann int; v_coaches int;
begin
  select count(*) into v_ann from public.announcements
    where academy_id = current_setting('cri.academy')::uuid;
  if v_ann < 2 then raise exception 'FAIL: owner cannot see all announcements'; end if;

  select count(*) into v_coaches from public.coaches
    where academy_id = current_setting('cri.academy')::uuid;
  if v_coaches < 2 then raise exception 'FAIL: owner cannot see all coaches'; end if;
  raise notice 'PASS: owner — academy-wide reads intact';
end $$;

reset role;
rollback;




-- ##########################################################################
-- ## rls_capabilities.sql
-- ##########################################################################

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
  v_coach_hc1 uuid;
  v_coach_other uuid;
  v_sport_cricket uuid;
  v_sport_football uuid;
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

  -- head_coach hc1 has a coaches row + is qualified for cricket only (C1).
  -- Phase 2 (20260607000200) scopes a head_coach to their center AND sport.
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_hc1, 'Head', 'Coach1') returning id into v_coach_hc1;
  select id into v_sport_cricket  from public.sports where code = 'cricket';
  select id into v_sport_football from public.sports where code = 'football';
  insert into public.coach_sports (academy_id, coach_id, sport_id)
  values (v_academy, v_coach_hc1, v_sport_cricket);

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
  perform set_config('cap.sport_cricket', v_sport_cricket::text, true);
  perform set_config('cap.sport_football', v_sport_football::text, true);

  raise notice '[cap setup] academy %, centers % %', v_academy, v_c1, v_c2;
end $$;

-- ---------- C1: trainer — attendance + performance on own batch; other no ---
-- Phase 3 (20260607000300) grants trainers performance, scoped to batches they
-- staff (here tr1 is the coach_id of b2). A batch they don't staff (b1) stays
-- denied for both.

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0e00-0000-0000-000000000006';  -- tr1

do $$
declare
  v_academy uuid := current_setting('cap.academy')::uuid;
  v_b1 uuid := current_setting('cap.b1')::uuid;
  v_b2 uuid := current_setting('cap.b2')::uuid;
  v_s1 uuid := current_setting('cap.s1')::uuid;
  v_caught boolean := false;
begin
  -- Own batch (b2): attendance + performance allowed.
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b2, v_s1, current_date, 'present', 'manual');
    insert into public.performance_assessments
      (academy_id, student_id, batch_id, assessment_date, overall_score)
    values (v_academy, v_s1, v_b2, current_date, 7.0);
  exception when others then
    raise exception 'FAIL: trainer blocked on own batch (attendance/performance): %', SQLERRM;
  end;

  -- A batch they do NOT staff (b1, owned by co1): attendance denied.
  v_caught := false;
  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy, v_b1, v_s1, current_date + 1, 'present', 'manual');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: trainer marked attendance on a batch they do not staff';
  end if;

  -- A batch they do NOT staff (b1): performance denied.
  v_caught := false;
  begin
    insert into public.performance_assessments
      (academy_id, student_id, batch_id, assessment_date, overall_score)
    values (v_academy, v_s1, v_b1, current_date, 6.0);
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: trainer recorded performance on a batch they do not staff';
  end if;
  raise notice 'PASS: trainer — own-batch attendance + performance, other batch blocked';
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

-- ---------- C4: head_coach — batches in own center + OWN SPORT; no students --

set local request.jwt.claim.sub = '00000000-0e00-0000-0000-000000000004';  -- hc1 (C1, cricket)

do $$
declare
  v_academy uuid := current_setting('cap.academy')::uuid;
  v_c1 uuid := current_setting('cap.c1')::uuid;
  v_c2 uuid := current_setting('cap.c2')::uuid;
  v_cricket uuid := current_setting('cap.sport_cricket')::uuid;
  v_football uuid := current_setting('cap.sport_football')::uuid;
  v_caught boolean := false;
begin
  -- Batch in own center AND own sport (cricket) → allowed.
  begin
    insert into public.batches (academy_id, center_id, sport_id, name)
    values (v_academy, v_c1, v_cricket, 'HC cricket C1');
  exception when others then
    raise exception 'FAIL: head_coach could not create a batch in own center+sport: %', SQLERRM;
  end;

  -- Batch in own center but a sport they do NOT coach (football) → denied.
  v_caught := false;
  begin
    insert into public.batches (academy_id, center_id, sport_id, name)
    values (v_academy, v_c1, v_football, 'HC football C1');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: head_coach created a batch in a sport they do not coach';
  end if;

  -- Batch in their sport but another center → denied.
  v_caught := false;
  begin
    insert into public.batches (academy_id, center_id, sport_id, name)
    values (v_academy, v_c2, v_cricket, 'HC cricket C2');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: head_coach created a batch in a center they do not manage';
  end if;

  -- A sport-less batch in own center IS head_coach-manageable: 20260607000600
  -- relaxed the strict sport gate so untagged batches fall back to center scope.
  begin
    insert into public.batches (academy_id, center_id, name)
    values (v_academy, v_c1, 'HC no-sport C1');
  exception when others then
    raise exception 'FAIL: head_coach could not create a sport-less batch in own center: %', SQLERRM;
  end;

  -- Students: head_coach CAN create in own center (20260607000700), NOT another.
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c1, 'HC', 'Student', 'Parent');
  exception when others then
    raise exception 'FAIL: head_coach could not create a student in own center: %', SQLERRM;
  end;

  v_caught := false;
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c2, 'HC', 'StudentC2', 'Parent');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: head_coach created a student in a center they do not manage';
  end if;
  raise notice 'PASS: head_coach — batches scoped to own center+sport; students own-center only';
end $$;

-- ---------- C5: coach — creates students (own center) but NOT batches -------

set local request.jwt.claim.sub = '00000000-0e00-0000-0000-000000000005';  -- co1 (C1)

do $$
declare
  v_academy uuid := current_setting('cap.academy')::uuid;
  v_c1 uuid := current_setting('cap.c1')::uuid;
  v_c2 uuid := current_setting('cap.c2')::uuid;
  v_caught boolean := false;
begin
  -- Batches are NOT a coach capability.
  begin
    insert into public.batches (academy_id, center_id, name)
    values (v_academy, v_c1, 'Coach sneaky batch');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: coach created a batch';
  end if;

  -- Students: coach CAN create in own center (20260607000700).
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c1, 'Coach', 'Student', 'Parent');
  exception when others then
    raise exception 'FAIL: coach could not create a student in own center: %', SQLERRM;
  end;

  -- ...but NOT in another center.
  v_caught := false;
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (v_academy, v_c2, 'Coach', 'StudentC2', 'Parent');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: coach created a student in a center they do not manage';
  end if;
  raise notice 'PASS: coach — creates students (own center) but not batches';
end $$;

-- ---------- Reset and roll back ---------------------------------------------

reset role;
rollback;




-- ##########################################################################
-- ## rls_trainer_media.sql
-- ##########################################################################

-- ============================================================================
-- Trainer standalone-media write capability regression test.
--
-- Verifies 20260606000000_trainer_student_media.sql:
--   * a TRAINER can attach standalone media (assessment_id null) to a student
--     enrolled in a batch they run — table row AND storage object;
--   * a trainer CANNOT attach media for a student outside their batches;
--   * a trainer still CANNOT create a scored performance_assessment;
--   * a PARENT cannot attach student media at all.
--
-- Runs in a transaction and rolls back. Any 'FAIL' raises and aborts.
-- ============================================================================


begin;

-- ---------- Setup (service role / superuser) --------------------------------

do $$
declare
  v_trainer constant uuid := '00000000-7777-0000-0000-000000000001';
  v_parent  constant uuid := '00000000-7777-0000-0000-000000000002';
  v_academy uuid;
  v_center  uuid;
  v_coach   uuid;  -- coaches row owned by the trainer
  v_batch   uuid;
  v_student_x uuid;  -- enrolled in the trainer's batch
  v_student_z uuid;  -- NOT in the trainer's batch
begin
  insert into auth.users (
    id, instance_id, email, role, aud,
    email_confirmed_at, created_at, updated_at
  )
  values
    (v_trainer, '00000000-0000-0000-0000-000000000000',
     'trainer-media@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now()),
    (v_parent, '00000000-0000-0000-0000-000000000000',
     'parent-media@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name)
    values ('Trainer Media Academy') returning id into v_academy;
  insert into public.centers (academy_id, name)
    values (v_academy, 'Centre') returning id into v_center;

  insert into public.users
    (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_trainer, 'trainer', v_academy, v_center, 'Trainer', 'T',
     'trainer-media@example.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id,
        center_id = excluded.center_id;

  insert into public.users
    (id, role, academy_id, first_name, last_name, email)
  values
    (v_parent, 'parent', v_academy, 'Parent', 'P',
     'parent-media@example.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id;

  -- coaches row owned by the trainer, assigned as the batch's coach.
  insert into public.coaches
    (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_center, v_trainer, 'Trainer', 'T')
  returning id into v_coach;

  insert into public.batches (academy_id, center_id, name, coach_id)
  values (v_academy, v_center, 'Batch', v_coach) returning id into v_batch;

  insert into public.students
    (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_center, 'Child', 'X', 'P')
  returning id into v_student_x;
  insert into public.students
    (academy_id, center_id, first_name, last_name, parent_name)
  values (v_academy, v_center, 'Child', 'Z', 'Q')
  returning id into v_student_z;

  insert into public.batch_enrollments (academy_id, batch_id, student_id)
  values (v_academy, v_batch, v_student_x);

  perform set_config('test.academy', v_academy::text, true);
  perform set_config('test.student_x', v_student_x::text, true);
  perform set_config('test.student_z', v_student_z::text, true);
end $$;

-- ---------- As the TRAINER --------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-7777-0000-0000-000000000001';

do $$
declare
  v_academy uuid := current_setting('test.academy')::uuid;
  v_x uuid := current_setting('test.student_x')::uuid;
  v_z uuid := current_setting('test.student_z')::uuid;
  v_caught boolean := false;
begin
  -- Allowed: standalone media for a student in the trainer's batch.
  insert into public.performance_media
    (academy_id, student_id, media_type, file_path)
  values (v_academy, v_x, 'photo',
          v_academy::text || '/students/' || v_x::text || '/a.jpg');
  raise notice 'PASS: trainer attached standalone media for own-batch student';

  -- Allowed: the backing storage object (widened bucket insert policy).
  insert into storage.objects (bucket_id, name, metadata)
  values ('performance_media',
          v_academy::text || '/students/' || v_x::text || '/a.jpg', '{}');
  raise notice 'PASS: trainer can write to performance_media storage';

  -- Denied: a student NOT in the trainer's batch.
  begin
    insert into public.performance_media
      (academy_id, student_id, media_type, file_path)
    values (v_academy, v_z, 'photo',
            v_academy::text || '/students/' || v_z::text || '/b.jpg');
  exception when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: trainer attached media for a non-batch student';
  end if;
  raise notice 'PASS: trainer blocked from non-batch student media';

  -- Denied: a FREE-STANDING (no-batch) scored assessment. Since Phase 3
  -- (20260607000300) trainers CAN record performance, but only against a batch
  -- they staff — a null batch_id has no scope to check, so it stays denied.
  -- (The allowed batch-scoped case is covered by rls_batch_staff.sql.)
  v_caught := false;
  begin
    insert into public.performance_assessments
      (academy_id, student_id, overall_score)
    values (v_academy, v_x, 7.0);
  exception when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: trainer created a free-standing (no-batch) assessment';
  end if;
  raise notice 'PASS: trainer cannot record a free-standing (no-batch) assessment';
end $$;

-- ---------- As the PARENT — cannot upload at all ----------------------------

set local request.jwt.claim.sub = '00000000-7777-0000-0000-000000000002';

do $$
declare
  v_academy uuid := current_setting('test.academy')::uuid;
  v_x uuid := current_setting('test.student_x')::uuid;
  v_caught boolean := false;
begin
  begin
    insert into public.performance_media
      (academy_id, student_id, media_type, file_path)
    values (v_academy, v_x, 'photo',
            v_academy::text || '/students/' || v_x::text || '/c.jpg');
  exception when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: parent uploaded student media';
  end if;
  raise notice 'PASS: parent cannot upload student media';
end $$;

reset role;
rollback;


