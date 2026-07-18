-- ============================================================================
-- head_coach coaches-read scope regression test
-- (20260608000100_head_coach_coaches_read_scope.sql).
--
--   head_coach (C1, cricket) can SELECT:
--     • a cricket coach in C1            → yes
--     • a sport-less coach in C1         → yes (NULL-sport fallback)
--     • a football coach in C1           → NO (not their sport)
--     • a cricket coach in C2            → NO (not their center)
--   center_admin (C1) still sees all C1 coaches (unchanged).
--
-- Visibility is asserted by row count under RLS. Same harness as
-- rls_capabilities.sql: transaction + rollback, impersonate via jwt.claim.sub.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner constant uuid := '00000000-0b00-0000-0000-000000000001';
  v_ca1   constant uuid := '00000000-0b00-0000-0000-000000000003';
  v_hc1   constant uuid := '00000000-0b00-0000-0000-000000000004';
  v_academy uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_coach_hc1 uuid;
  v_sport_cricket uuid;
  v_sport_football uuid;
  v_cricket_c1 uuid;
  v_football_c1 uuid;
  v_cricket_c2 uuid;
  v_nosport_c1 uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'cr-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'cr-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_hc1,   '00000000-0000-0000-0000-000000000000', 'cr-hc1@x.invalid',   'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id)
  values ('Coach-read Academy', v_owner) returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1') returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_academy, 'C2') returning id into v_c2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O',  'cr-owner@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'Center', 'A', 'cr-ca1@x.invalid'),
    (v_hc1,   'head_coach',    v_academy, v_c1, 'Head', 'C',   'cr-hc1@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  select id into v_sport_cricket  from public.sports where code = 'cricket';
  select id into v_sport_football from public.sports where code = 'football';

  -- head_coach hc1 is qualified for cricket only.
  insert into public.coaches (academy_id, center_id, user_id, first_name, last_name)
  values (v_academy, v_c1, v_hc1, 'Head', 'C') returning id into v_coach_hc1;
  insert into public.coach_sports (academy_id, coach_id, sport_id)
  values (v_academy, v_coach_hc1, v_sport_cricket);

  -- Test coaches.
  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c1, 'Cricket', 'C1') returning id into v_cricket_c1;
  insert into public.coach_sports (academy_id, coach_id, sport_id)
  values (v_academy, v_cricket_c1, v_sport_cricket);

  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c1, 'Football', 'C1') returning id into v_football_c1;
  insert into public.coach_sports (academy_id, coach_id, sport_id)
  values (v_academy, v_football_c1, v_sport_football);

  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c2, 'Cricket', 'C2') returning id into v_cricket_c2;
  insert into public.coach_sports (academy_id, coach_id, sport_id)
  values (v_academy, v_cricket_c2, v_sport_cricket);

  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c1, 'NoSport', 'C1') returning id into v_nosport_c1;

  perform set_config('cr.cricket_c1',  v_cricket_c1::text,  true);
  perform set_config('cr.football_c1', v_football_c1::text, true);
  perform set_config('cr.cricket_c2',  v_cricket_c2::text,  true);
  perform set_config('cr.nosport_c1',  v_nosport_c1::text,  true);
end $$;

set local role authenticated;

-- ---------- head_coach hc1 (C1, cricket) ------------------------------------
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000004';

do $$
declare
  v_cricket_c1 uuid := current_setting('cr.cricket_c1')::uuid;
  v_football_c1 uuid := current_setting('cr.football_c1')::uuid;
  v_cricket_c2 uuid := current_setting('cr.cricket_c2')::uuid;
  v_nosport_c1 uuid := current_setting('cr.nosport_c1')::uuid;
begin
  if (select count(*) from public.coaches where id = v_cricket_c1) <> 1 then
    raise exception 'FAIL: head_coach cannot see a cricket coach in own center';
  end if;
  if (select count(*) from public.coaches where id = v_nosport_c1) <> 1 then
    raise exception 'FAIL: head_coach cannot see a sport-less coach in own center';
  end if;
  if (select count(*) from public.coaches where id = v_football_c1) <> 0 then
    raise exception 'FAIL: head_coach can see a football coach (not their sport)';
  end if;
  if (select count(*) from public.coaches where id = v_cricket_c2) <> 0 then
    raise exception 'FAIL: head_coach can see a coach in another center';
  end if;
  raise notice 'PASS: head_coach — own center + own sport (and untagged) only';
end $$;

-- ---------- center_admin ca1 (C1) still sees all C1 coaches -----------------
set local request.jwt.claim.sub = '00000000-0b00-0000-0000-000000000003';

do $$
declare
  v_cricket_c1 uuid := current_setting('cr.cricket_c1')::uuid;
  v_football_c1 uuid := current_setting('cr.football_c1')::uuid;
  v_cricket_c2 uuid := current_setting('cr.cricket_c2')::uuid;
begin
  if (select count(*) from public.coaches where id = v_cricket_c1) <> 1
     or (select count(*) from public.coaches where id = v_football_c1) <> 1 then
    raise exception 'FAIL: center_admin lost visibility of a coach in own center';
  end if;
  if (select count(*) from public.coaches where id = v_cricket_c2) <> 0 then
    raise exception 'FAIL: center_admin can see a coach in another center';
  end if;
  raise notice 'PASS: center_admin — all own-center coaches, no cross-center';
end $$;

rollback;
