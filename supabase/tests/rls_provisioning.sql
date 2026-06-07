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

\set ON_ERROR_STOP on
\set ECHO none

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

\echo 'All provisioning-ladder tests passed.'
