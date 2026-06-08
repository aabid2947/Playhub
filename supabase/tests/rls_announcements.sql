-- ============================================================================
-- Announcement compose-scope regression test.
--
-- Asserts can_target_announcement() via real INSERTs into public.announcements
-- (20260608000000_announcement_compose_and_media.sql):
--
--   • coach        → own batch yes; other batch / center / empty / roles NO
--   • head_coach   → own-center+own-sport batch yes; own sport yes;
--                    other sport / center NO
--   • center_admin → own center yes; other center NO; own-center sport yes
--   • owner        → empty (everyone) + role targeting yes
--
-- Same harness as rls_capabilities.sql: runs in a transaction, rolls back,
-- impersonates by setting request.jwt.claim.sub. Any 'FAIL' aborts.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

-- ---------- Setup (superuser; RLS bypassed) ---------------------------------

do $$
declare
  v_owner constant uuid := '00000000-0a00-0000-0000-000000000001';
  v_ca1   constant uuid := '00000000-0a00-0000-0000-000000000003';
  v_hc1   constant uuid := '00000000-0a00-0000-0000-000000000004';
  v_co1   constant uuid := '00000000-0a00-0000-0000-000000000005';
  v_academy uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_coach_co1 uuid;
  v_coach_hc1 uuid;
  v_coach_other uuid;
  v_sport_cricket uuid;
  v_sport_football uuid;
  v_b1 uuid;  -- C1, cricket, owned by co1
  v_b3 uuid;  -- C2, owned by neither
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'ann-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'ann-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_hc1,   '00000000-0000-0000-0000-000000000000', 'ann-hc1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_co1,   '00000000-0000-0000-0000-000000000000', 'ann-co1@x.invalid',   'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id)
  values ('Announcement Academy', v_owner)
  returning id into v_academy;

  insert into public.centers (academy_id, name) values (v_academy, 'C1')
  returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_academy, 'C2')
  returning id into v_c2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O',  'ann-owner@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'Center', 'A', 'ann-ca1@x.invalid'),
    (v_hc1,   'head_coach',    v_academy, v_c1, 'Head', 'C',   'ann-hc1@x.invalid'),
    (v_co1,   'coach',         v_academy, v_c1, 'Coach', 'O',  'ann-co1@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id,
        center_id = excluded.center_id;

  -- coach co1 has a coaches row (owns b1); head_coach hc1 is qualified for
  -- cricket only; a third coach sits in C2.
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_co1, 'Coach', 'O') returning id into v_coach_co1;
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_hc1, 'Head', 'C') returning id into v_coach_hc1;
  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c2, 'Other', 'Coach') returning id into v_coach_other;

  select id into v_sport_cricket  from public.sports where code = 'cricket';
  select id into v_sport_football from public.sports where code = 'football';
  insert into public.coach_sports (academy_id, coach_id, sport_id)
  values (v_academy, v_coach_hc1, v_sport_cricket);

  -- cricket is enabled for C1 (so center_admin may target it); football is not.
  insert into public.center_sports (academy_id, center_id, sport_id)
  values (v_academy, v_c1, v_sport_cricket);

  insert into public.batches (academy_id, center_id, coach_id, sport_id, name)
  values (v_academy, v_c1, v_coach_co1, v_sport_cricket, 'B1') returning id into v_b1;
  insert into public.batches (academy_id, center_id, coach_id, name)
  values (v_academy, v_c2, v_coach_other, 'B3') returning id into v_b3;

  perform set_config('ann.academy', v_academy::text, true);
  perform set_config('ann.c1', v_c1::text, true);
  perform set_config('ann.c2', v_c2::text, true);
  perform set_config('ann.b1', v_b1::text, true);
  perform set_config('ann.b3', v_b3::text, true);
  perform set_config('ann.cricket', v_sport_cricket::text, true);
  perform set_config('ann.football', v_sport_football::text, true);
end $$;

-- ---------- coach co1 — own batch only --------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000005';  -- co1

do $$
declare
  v_academy uuid := current_setting('ann.academy')::uuid;
  v_c1 uuid := current_setting('ann.c1')::uuid;
  v_b1 uuid := current_setting('ann.b1')::uuid;
  v_b3 uuid := current_setting('ann.b3')::uuid;
  v_caught boolean;
begin
  -- Own batch → allowed.
  begin
    insert into public.announcements
      (academy_id, subject, body, target_batches, created_by)
    values (v_academy, 'Hi', 'msg', array[v_b1], auth.uid());
  exception when others then
    raise exception 'FAIL: coach could not announce to own batch: %', SQLERRM;
  end;

  -- Batch they do not own → denied.
  v_caught := false;
  begin
    insert into public.announcements
      (academy_id, subject, body, target_batches, created_by)
    values (v_academy, 'Hi', 'msg', array[v_b3], auth.uid());
  exception when others then v_caught := true;
  end;
  if not v_caught then raise exception 'FAIL: coach announced to a batch they do not own'; end if;

  -- Center targeting → denied.
  v_caught := false;
  begin
    insert into public.announcements
      (academy_id, subject, body, target_centers, created_by)
    values (v_academy, 'Hi', 'msg', array[v_c1], auth.uid());
  exception when others then v_caught := true;
  end;
  if not v_caught then raise exception 'FAIL: coach targeted a whole center'; end if;

  -- Empty targets (everyone) → denied.
  v_caught := false;
  begin
    insert into public.announcements (academy_id, subject, body, created_by)
    values (v_academy, 'Hi', 'msg', auth.uid());
  exception when others then v_caught := true;
  end;
  if not v_caught then raise exception 'FAIL: coach broadcast to everyone (empty targets)'; end if;

  -- Role targeting → denied.
  v_caught := false;
  begin
    insert into public.announcements
      (academy_id, subject, body, target_roles, created_by)
    values (v_academy, 'Hi', 'msg', array['parent']::public.user_role[], auth.uid());
  exception when others then v_caught := true;
  end;
  if not v_caught then raise exception 'FAIL: coach targeted by role'; end if;

  raise notice 'PASS: coach — own batch only';
end $$;

-- ---------- head_coach hc1 — own center + own sport -------------------------

set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000004';  -- hc1 (C1, cricket)

do $$
declare
  v_academy uuid := current_setting('ann.academy')::uuid;
  v_c1 uuid := current_setting('ann.c1')::uuid;
  v_b1 uuid := current_setting('ann.b1')::uuid;
  v_cricket uuid := current_setting('ann.cricket')::uuid;
  v_football uuid := current_setting('ann.football')::uuid;
  v_caught boolean;
begin
  -- Own-center + own-sport batch → allowed.
  begin
    insert into public.announcements
      (academy_id, subject, body, target_batches, created_by)
    values (v_academy, 'Hi', 'msg', array[v_b1], auth.uid());
  exception when others then
    raise exception 'FAIL: head_coach could not announce to own-center+sport batch: %', SQLERRM;
  end;

  -- Own sport → allowed.
  begin
    insert into public.announcements
      (academy_id, subject, body, target_sports, created_by)
    values (v_academy, 'Hi', 'msg', array[v_cricket], auth.uid());
  exception when others then
    raise exception 'FAIL: head_coach could not announce to own sport: %', SQLERRM;
  end;

  -- A sport they do not coach → denied.
  v_caught := false;
  begin
    insert into public.announcements
      (academy_id, subject, body, target_sports, created_by)
    values (v_academy, 'Hi', 'msg', array[v_football], auth.uid());
  exception when others then v_caught := true;
  end;
  if not v_caught then raise exception 'FAIL: head_coach targeted a sport they do not coach'; end if;

  -- Center targeting → denied.
  v_caught := false;
  begin
    insert into public.announcements
      (academy_id, subject, body, target_centers, created_by)
    values (v_academy, 'Hi', 'msg', array[v_c1], auth.uid());
  exception when others then v_caught := true;
  end;
  if not v_caught then raise exception 'FAIL: head_coach targeted a whole center'; end if;

  raise notice 'PASS: head_coach — own center + own sport';
end $$;

-- ---------- center_admin ca1 — own center -----------------------------------

set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000003';  -- ca1 (C1)

do $$
declare
  v_academy uuid := current_setting('ann.academy')::uuid;
  v_c1 uuid := current_setting('ann.c1')::uuid;
  v_c2 uuid := current_setting('ann.c2')::uuid;
  v_cricket uuid := current_setting('ann.cricket')::uuid;
  v_caught boolean;
begin
  -- Own center → allowed.
  begin
    insert into public.announcements
      (academy_id, subject, body, target_centers, created_by)
    values (v_academy, 'Hi', 'msg', array[v_c1], auth.uid());
  exception when others then
    raise exception 'FAIL: center_admin could not announce to own center: %', SQLERRM;
  end;

  -- Sport enabled in own center → allowed.
  begin
    insert into public.announcements
      (academy_id, subject, body, target_sports, created_by)
    values (v_academy, 'Hi', 'msg', array[v_cricket], auth.uid());
  exception when others then
    raise exception 'FAIL: center_admin could not announce to an own-center sport: %', SQLERRM;
  end;

  -- Other center → denied.
  v_caught := false;
  begin
    insert into public.announcements
      (academy_id, subject, body, target_centers, created_by)
    values (v_academy, 'Hi', 'msg', array[v_c2], auth.uid());
  exception when others then v_caught := true;
  end;
  if not v_caught then raise exception 'FAIL: center_admin targeted a center they do not manage'; end if;

  raise notice 'PASS: center_admin — own center';
end $$;

-- ---------- owner — everyone + role targeting -------------------------------

set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000001';  -- owner

do $$
declare
  v_academy uuid := current_setting('ann.academy')::uuid;
begin
  -- Empty targets (everyone) → allowed for admin tier.
  begin
    insert into public.announcements (academy_id, subject, body, created_by)
    values (v_academy, 'All', 'msg', auth.uid());
    insert into public.announcements
      (academy_id, subject, body, target_roles, created_by)
    values (v_academy, 'Parents', 'msg', array['parent']::public.user_role[], auth.uid());
  exception when others then
    raise exception 'FAIL: owner blocked on academy-wide / role targeting: %', SQLERRM;
  end;
  raise notice 'PASS: owner — everyone + role targeting';
end $$;

rollback;
