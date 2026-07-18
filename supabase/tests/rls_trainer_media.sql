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

\set ON_ERROR_STOP on
\set ECHO none

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

\echo 'All trainer-media tests passed.'
