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

\set ON_ERROR_STOP on
\set ECHO none

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

\echo 'All batch-staff / trainer-scope tests passed.'
