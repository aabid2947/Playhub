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

\set ON_ERROR_STOP on
\set ECHO none

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

\echo 'All sport-scope tests passed.'
