-- ============================================================================
-- Parent/student WITHIN-academy scoping regression test.
--
-- rls_tenancy.sql proves cross-ACADEMY isolation. This proves the finer
-- within-academy rule the "distribute performance media to the right parent /
-- student" feature depends on: a parent linked to child X must NOT see a
-- *different* child Y's performance (assessment, skills, media) or media
-- files, even though X and Y share one academy. A self-login student must
-- likewise see only their own.
--
-- Exercises:
--   * parent_can_see_student() narrowing on performance_assessments /
--     performance_skills / performance_media   (20260508000000_parent_links)
--   * the performance_media storage-bucket SELECT policy
--     (20260605000000_perf_media_parent_scope)
--
-- Runs in a transaction and rolls back, so re-running is idempotent. Any
-- 'FAIL' raises an exception and aborts.
--
-- Run locally:
--   supabase db reset
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d \")" \
--        -f supabase/tests/rls_parent_student_scope.sql
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

-- ---------- Setup (as service role / superuser) -----------------------------

do $$
declare
  v_parent        constant uuid := '00000000-9111-0000-0000-000000000001';
  v_student_login constant uuid := '00000000-9111-0000-0000-000000000002';
  v_academy uuid;
  v_center  uuid;
  v_student_x uuid;  -- linked to the parent / mapped to the self-login student
  v_student_y uuid;  -- a different child in the SAME academy
  v_assess_x uuid;
  v_assess_y uuid;
begin
  insert into auth.users (
    id, instance_id, email, role, aud,
    email_confirmed_at, created_at, updated_at
  )
  values
    (v_parent, '00000000-0000-0000-0000-000000000000',
     'scope-parent@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now()),
    (v_student_login, '00000000-0000-0000-0000-000000000000',
     'scope-student@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name)
    values ('Scope Test Academy') returning id into v_academy;

  insert into public.centers (academy_id, name)
    values (v_academy, 'Scope Centre') returning id into v_center;

  -- public.users rows (the auth trigger creates stubs; set role + academy).
  insert into public.users
    (id, role, academy_id, first_name, last_name, email)
  values
    (v_parent, 'parent', v_academy, 'Scope', 'Parent',
     'scope-parent@example.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id;

  -- Two students in the SAME academy.
  insert into public.students (academy_id, first_name, last_name, parent_name)
    values (v_academy, 'Child', 'X', 'Scope Parent')
    returning id into v_student_x;
  insert into public.students (academy_id, first_name, last_name, parent_name)
    values (v_academy, 'Child', 'Y', 'Other Parent')
    returning id into v_student_y;

  -- The self-login student maps to child X (student-self path).
  insert into public.users
    (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_student_login, 'student', v_academy, v_center, 'Child', 'X',
     'scope-student@example.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id;
  update public.students set user_id = v_student_login where id = v_student_x;

  -- Parent linked to child X ONLY.
  insert into public.parent_links (academy_id, parent_user_id, student_id)
    values (v_academy, v_parent, v_student_x);

  -- One assessment + skill + media row per child.
  insert into public.performance_assessments
    (academy_id, student_id, overall_score)
    values (v_academy, v_student_x, 8.0) returning id into v_assess_x;
  insert into public.performance_assessments
    (academy_id, student_id, overall_score)
    values (v_academy, v_student_y, 7.0) returning id into v_assess_y;

  insert into public.performance_skills
    (assessment_id, academy_id, student_id, skill_name, score)
  values
    (v_assess_x, v_academy, v_student_x, 'Footwork', 8),
    (v_assess_y, v_academy, v_student_y, 'Footwork', 7);

  insert into public.performance_media
    (assessment_id, academy_id, student_id, media_type, file_path)
  values
    (v_assess_x, v_academy, v_student_x, 'video',
       v_academy::text || '/assessments/' || v_assess_x::text || '/x.mp4'),
    (v_assess_y, v_academy, v_student_y, 'video',
       v_academy::text || '/assessments/' || v_assess_y::text || '/y.mp4');

  -- Storage objects backing those media rows.
  insert into storage.objects (bucket_id, name, metadata)
  values
    ('performance_media',
       v_academy::text || '/assessments/' || v_assess_x::text || '/x.mp4', '{}'),
    ('performance_media',
       v_academy::text || '/assessments/' || v_assess_y::text || '/y.mp4', '{}');

  perform set_config('test.parent', v_parent::text, true);
  perform set_config('test.student_login', v_student_login::text, true);
  perform set_config('test.academy', v_academy::text, true);
  perform set_config('test.student_x', v_student_x::text, true);
  perform set_config('test.student_y', v_student_y::text, true);

  raise notice '[setup] academy %, child X %, child Y %',
    v_academy, v_student_x, v_student_y;
end $$;

-- ---------- Test 1: parent (linked to X) sees only X in the tables ----------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-9111-0000-0000-000000000001';

do $$
declare
  v_x uuid := current_setting('test.student_x')::uuid;
  v_y uuid := current_setting('test.student_y')::uuid;
  v_own int;
  v_other int;
begin
  -- students
  select count(*) into v_own   from public.students where id = v_x;
  select count(*) into v_other from public.students where id = v_y;
  if v_own = 0 then
    raise exception 'FAIL: parent could not read their own child (X)';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: parent read a different child (Y) in same academy';
  end if;

  -- performance_assessments
  select count(*) into v_own
    from public.performance_assessments where student_id = v_x;
  select count(*) into v_other
    from public.performance_assessments where student_id = v_y;
  if v_own = 0 then
    raise exception 'FAIL: parent could not read own child performance';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: parent read child Y performance (% rows)', v_other;
  end if;

  -- performance_skills
  select count(*) into v_other
    from public.performance_skills where student_id = v_y;
  if v_other > 0 then
    raise exception 'FAIL: parent read child Y performance_skills';
  end if;

  -- performance_media (table)
  select count(*) into v_own
    from public.performance_media where student_id = v_x;
  select count(*) into v_other
    from public.performance_media where student_id = v_y;
  if v_own = 0 then
    raise exception 'FAIL: parent could not read own child media rows';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: parent read child Y media rows';
  end if;

  raise notice
    'PASS: parent sees only own child performance (assess/skills/media)';
end $$;

-- ---------- Test 2: parent sees only X's media FILE (storage policy) --------
-- The academy has exactly two performance_media objects (X's + Y's); the
-- parent must see exactly one.

do $$
declare
  v_academy text := current_setting('test.academy');
  v_visible int;
begin
  select count(*) into v_visible from storage.objects
    where bucket_id = 'performance_media'
      and name like v_academy || '/%';
  if v_visible <> 1 then
    raise exception
      'FAIL: parent sees % performance_media objects (expected 1 = own child)',
      v_visible;
  end if;
  raise notice 'PASS: performance_media storage scoped to own child (parent)';
end $$;

-- ---------- Test 3: self-login student (mapped to X) — same scoping ---------

set local request.jwt.claim.sub = '00000000-9111-0000-0000-000000000002';

do $$
declare
  v_x uuid := current_setting('test.student_x')::uuid;
  v_y uuid := current_setting('test.student_y')::uuid;
  v_academy text := current_setting('test.academy');
  v_own int;
  v_other int;
  v_visible int;
begin
  select count(*) into v_own
    from public.performance_media where student_id = v_x;
  select count(*) into v_other
    from public.performance_media where student_id = v_y;
  if v_own = 0 then
    raise exception 'FAIL: student could not read own media rows';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: student read another child''s media rows';
  end if;

  select count(*) into v_visible from storage.objects
    where bucket_id = 'performance_media'
      and name like v_academy || '/%';
  if v_visible <> 1 then
    raise exception
      'FAIL: student sees % performance_media objects (expected 1 = self)',
      v_visible;
  end if;

  raise notice 'PASS: self-login student sees only their own performance media';
end $$;

-- ---------- Reset and roll back --------------------------------------------

reset role;
rollback;

\echo 'All parent/student scope tests passed.'
