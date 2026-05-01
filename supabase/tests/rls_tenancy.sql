-- ============================================================================
-- Tenant-isolation regression test
--
-- Asserts that an authenticated user from Academy A cannot read or write
-- data belonging to Academy B. The whole script runs in a transaction and
-- rolls back at the end, so re-running is idempotent.
--
-- Run locally:
--   supabase db reset                           # apply all migrations fresh
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d \")" \
--        -f supabase/tests/rls_tenancy.sql
--
-- Run against staging (read-only via rollback):
--   psql "$DATABASE_URL" -f supabase/tests/rls_tenancy.sql
--
-- Output: a series of NOTICE lines. Any 'FAIL' raises an exception and
-- aborts the transaction; otherwise you'll see 'PASS' lines.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

-- ---------- Setup (as service role / superuser) -----------------------------

-- Use deterministic UUIDs for the two test users / academies.
do $$
declare
  v_user_a constant uuid := '00000000-aaaa-0000-0000-000000000001';
  v_user_b constant uuid := '00000000-bbbb-0000-0000-000000000002';
  v_academy_a uuid;
  v_academy_b uuid;
begin
  -- auth.users entries (minimum columns required by the schema)
  insert into auth.users (
    id, instance_id, email, role, aud,
    email_confirmed_at, created_at, updated_at
  )
  values
    (v_user_a, '00000000-0000-0000-0000-000000000000',
     'rls-test-a@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now()),
    (v_user_b, '00000000-0000-0000-0000-000000000000',
     'rls-test-b@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now())
  on conflict (id) do nothing;

  -- public.users — the auth trigger creates stub rows; upsert to set role.
  insert into public.users (id, role, first_name, last_name, email)
  values
    (v_user_a, 'academy_owner', 'Test', 'A', 'rls-test-a@example.invalid'),
    (v_user_b, 'academy_owner', 'Test', 'B', 'rls-test-b@example.invalid')
  on conflict (id) do update
    set role = excluded.role,
        first_name = excluded.first_name,
        last_name = excluded.last_name;

  -- Academies (one per user)
  insert into public.academies (name, owner_id)
  values ('RLS Test Academy A', v_user_a)
  returning id into v_academy_a;

  insert into public.academies (name, owner_id)
  values ('RLS Test Academy B', v_user_b)
  returning id into v_academy_b;

  -- Link users to their academies
  update public.users set academy_id = v_academy_a where id = v_user_a;
  update public.users set academy_id = v_academy_b where id = v_user_b;

  -- A center + a student + a coach + a batch + an enrollment in each academy
  insert into public.centers (academy_id, name)
  values (v_academy_a, 'Centre A1'), (v_academy_b, 'Centre B1');

  insert into public.students (academy_id, first_name, last_name, parent_name)
  values
    (v_academy_a, 'Aarav', 'A', 'Parent A'),
    (v_academy_b, 'Bhavya', 'B', 'Parent B');

  insert into public.coaches (academy_id, first_name, last_name)
  values
    (v_academy_a, 'Coach', 'A1'),
    (v_academy_b, 'Coach', 'B1');

  insert into public.batches (academy_id, name)
  values
    (v_academy_a, 'Batch A1'),
    (v_academy_b, 'Batch B1');

  insert into public.batch_enrollments (academy_id, batch_id, student_id)
  select b.academy_id, b.id, s.id
  from public.batches b
  join public.students s on s.academy_id = b.academy_id;

  -- Storage objects in each bucket, one per academy. Path layout matches
  -- what StorageService writes from Flutter: <academy_id>/<entity>/...
  insert into storage.objects (bucket_id, name, metadata) values
    ('avatars',           v_academy_a::text || '/students/aaa.jpg', '{}'),
    ('avatars',           v_academy_b::text || '/students/bbb.jpg', '{}'),
    ('student_documents', v_academy_a::text || '/students/sa/aaa.pdf', '{}'),
    ('student_documents', v_academy_b::text || '/students/sb/bbb.pdf', '{}'),
    ('coach_documents',   v_academy_a::text || '/coaches/ca/aaa.pdf', '{}'),
    ('coach_documents',   v_academy_b::text || '/coaches/cb/bbb.pdf', '{}');

  -- Stash IDs in session-local config so the test phase can read them.
  perform set_config('test.user_a', v_user_a::text, true);
  perform set_config('test.user_b', v_user_b::text, true);
  perform set_config('test.academy_a', v_academy_a::text, true);
  perform set_config('test.academy_b', v_academy_b::text, true);

  raise notice '[setup] users: % %, academies: % %',
    v_user_a, v_user_b, v_academy_a, v_academy_b;
end $$;

-- ---------- Test 1: user A reads from public.students -----------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-aaaa-0000-0000-000000000001';

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.students where academy_id = v_academy_a;
  select count(*) into v_other
    from public.students where academy_id = v_academy_b;

  if v_own = 0 then
    raise exception 'FAIL: user A could not read their own academy''s students';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % rows from academy B', v_other;
  end if;
  raise notice 'PASS: students read isolation (% own, % other)', v_own, v_other;
end $$;

-- ---------- Test 2: user A reads from public.centers ------------------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.centers where academy_id = v_academy_a;
  select count(*) into v_other
    from public.centers where academy_id = v_academy_b;

  if v_own = 0 then
    raise exception 'FAIL: user A could not read their own academy''s centers';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % rows from centers in academy B', v_other;
  end if;
  raise notice 'PASS: centers read isolation';
end $$;

-- ---------- Test 3: user A cannot insert into academy B ---------------------

do $$
declare
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_caught boolean := false;
begin
  begin
    insert into public.students (academy_id, first_name, last_name, parent_name)
    values (v_academy_b, 'Sneaky', 'Insert', 'Should Fail');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A was able to insert into academy B';
  end if;
  raise notice 'PASS: cross-tenant insert blocked';
end $$;

-- ---------- Test 4: user A cannot read other user's profile -----------------

do $$
declare
  v_user_b uuid := current_setting('test.user_b')::uuid;
  v_count int;
begin
  select count(*) into v_count
    from public.users where id = v_user_b;
  if v_count > 0 then
    raise exception 'FAIL: user A read user B''s profile row';
  end if;
  raise notice 'PASS: cross-tenant user-profile read blocked';
end $$;

-- ---------- Test 5: coaches read isolation ---------------------------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.coaches where academy_id = v_academy_a;
  select count(*) into v_other
    from public.coaches where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own academy coaches';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % rows from academy B coaches', v_other;
  end if;
  raise notice 'PASS: coaches read isolation';
end $$;

-- ---------- Test 6: batches read isolation ---------------------------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.batches where academy_id = v_academy_a;
  select count(*) into v_other
    from public.batches where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own academy batches';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % rows from academy B batches', v_other;
  end if;
  raise notice 'PASS: batches read isolation';
end $$;

-- ---------- Test 7: batch_enrollments read isolation -----------------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.batch_enrollments where academy_id = v_academy_a;
  select count(*) into v_other
    from public.batch_enrollments where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own academy enrollments';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % enrollments from academy B', v_other;
  end if;
  raise notice 'PASS: enrollments read isolation';
end $$;

-- ---------- Test 8: audit_logs read isolation -----------------------------
-- The setup phase generated audit rows for academies A and B; user A may
-- only see those tagged with academy_a.

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.audit_logs where academy_id = v_academy_a;
  select count(*) into v_other
    from public.audit_logs where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own academy audit logs';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % audit_logs from academy B', v_other;
  end if;
  raise notice 'PASS: audit_logs read isolation';
end $$;

-- ---------- Test 9: audit_logs cannot be written from app layer ------------
-- There are no INSERT/UPDATE/DELETE policies; only the SECURITY DEFINER
-- trigger writes. So a direct insert from the app must fail.

do $$
declare
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_caught boolean := false;
begin
  begin
    insert into public.audit_logs (academy_id, action, entity_type)
    values (v_academy_a, 'insert', 'students');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: app-layer insert into audit_logs was allowed';
  end if;
  raise notice 'PASS: audit_logs app-layer writes blocked';
end $$;

-- ---------- Test 10: storage — avatars bucket -------------------------------
-- avatars is public, so SELECT is unrestricted. INSERT is the gate: the
-- top-level folder of the path must equal current_user_academy_id() AND
-- the user must be admin-or-higher.

do $$
declare
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_caught boolean := false;
begin
  -- Insert into own academy folder — should succeed.
  begin
    insert into storage.objects (bucket_id, name, metadata)
    values ('avatars', v_academy_a::text || '/students/own.jpg', '{}');
  exception when others then
    raise exception 'FAIL: user A could not insert avatar in own academy: %',
      SQLERRM;
  end;

  -- Insert into other academy folder — must fail.
  begin
    insert into storage.objects (bucket_id, name, metadata)
    values ('avatars', v_academy_b::text || '/students/sneaky.jpg', '{}');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted avatar into academy B folder';
  end if;
  raise notice 'PASS: avatars bucket — own write allowed, cross-tenant blocked';
end $$;

-- ---------- Test 11: storage — student_documents (private bucket) ----------
-- Private bucket: SELECT is itself gated by the same-academy policy.

do $$
declare
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_own int;
  v_other int;
  v_caught boolean := false;
begin
  select count(*) into v_own from storage.objects
    where bucket_id = 'student_documents'
      and name like v_academy_a::text || '/%';
  select count(*) into v_other from storage.objects
    where bucket_id = 'student_documents'
      and name like v_academy_b::text || '/%';

  if v_own = 0 then
    raise exception 'FAIL: user A could not read own student_documents';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % student_documents from academy B',
      v_other;
  end if;

  -- INSERT into other-academy folder must fail.
  begin
    insert into storage.objects (bucket_id, name, metadata)
    values ('student_documents',
            v_academy_b::text || '/students/sb/sneaky.pdf', '{}');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted student_doc into academy B folder';
  end if;

  raise notice 'PASS: student_documents — read isolation + cross-tenant insert blocked';
end $$;

-- ---------- Test 12: storage — coach_documents (private bucket) ------------

do $$
declare
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_own int;
  v_other int;
  v_caught boolean := false;
begin
  select count(*) into v_own from storage.objects
    where bucket_id = 'coach_documents'
      and name like v_academy_a::text || '/%';
  select count(*) into v_other from storage.objects
    where bucket_id = 'coach_documents'
      and name like v_academy_b::text || '/%';

  if v_own = 0 then
    raise exception 'FAIL: user A could not read own coach_documents';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % coach_documents from academy B',
      v_other;
  end if;

  begin
    insert into storage.objects (bucket_id, name, metadata)
    values ('coach_documents',
            v_academy_b::text || '/coaches/cb/sneaky.pdf', '{}');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted coach_doc into academy B folder';
  end if;

  raise notice 'PASS: coach_documents — read isolation + cross-tenant insert blocked';
end $$;

-- ---------- Test 13: cross-tenant batch insert blocked ---------------------

do $$
declare
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_caught boolean := false;
begin
  begin
    insert into public.batches (academy_id, name)
    values (v_academy_b, 'Sneaky cross-tenant batch');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted a batch into academy B';
  end if;
  raise notice 'PASS: cross-tenant batch insert blocked';
end $$;

-- ---------- Reset and roll back --------------------------------------------

reset role;
rollback;

\echo 'All RLS isolation tests passed.'
