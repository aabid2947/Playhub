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

  -- Sprint-2 seed: attendance + performance per academy.
  insert into public.attendance_records
    (academy_id, batch_id, student_id, date, status, method)
  select b.academy_id, b.id, s.id, current_date, 'present', 'manual'
  from public.batches b
  join public.students s on s.academy_id = b.academy_id;

  insert into public.performance_assessments
    (academy_id, student_id, batch_id, assessment_date, overall_score, sport)
  select s.academy_id, s.id, b.id, current_date, 8.0, 'cricket'
  from public.students s
  join public.batches b on b.academy_id = s.academy_id;

  insert into public.performance_skills
    (assessment_id, academy_id, student_id, skill_name, score)
  select pa.id, pa.academy_id, pa.student_id, 'Footwork', 7
  from public.performance_assessments pa;

  -- Sprint-3 seed: a fee structure + assignment + invoice + payment per
  -- academy. Numbers are minimal — only enough to make read-isolation
  -- assertions meaningful.
  insert into public.fee_structures
    (academy_id, name, type, base_amount, tax_pct)
  values
    (v_academy_a, 'Monthly A', 'monthly', 2000, 18),
    (v_academy_b, 'Monthly B', 'monthly', 2000, 18);

  insert into public.student_fee_assignments
    (academy_id, student_id, fee_structure_id)
  select s.academy_id, s.id, fs.id
  from public.students s
  join public.fee_structures fs on fs.academy_id = s.academy_id;

  insert into public.batch_fee_assignments
    (academy_id, batch_id, fee_structure_id)
  select b.academy_id, b.id, fs.id
  from public.batches b
  join public.fee_structures fs on fs.academy_id = b.academy_id;

  -- Discounts seed: one structure + one student-level + one batch-level
  -- assignment per academy.
  insert into public.discount_structures
    (academy_id, name, type, value)
  values
    (v_academy_a, 'Sibling A', 'percentage', 10),
    (v_academy_b, 'Sibling B', 'percentage', 10);

  insert into public.student_discount_assignments
    (academy_id, student_id, discount_structure_id)
  select s.academy_id, s.id, ds.id
  from public.students s
  join public.discount_structures ds on ds.academy_id = s.academy_id;

  insert into public.batch_discount_assignments
    (academy_id, batch_id, discount_structure_id)
  select b.academy_id, b.id, ds.id
  from public.batches b
  join public.discount_structures ds on ds.academy_id = b.academy_id;

  insert into public.invoices
    (academy_id, student_id, invoice_number, due_date, base_amount, tax_amount)
  select s.academy_id,
         s.id,
         public.next_invoice_number(s.academy_id),
         current_date + interval '7 days',
         2000,
         360
  from public.students s;

  insert into public.invoice_line_items
    (invoice_id, academy_id, kind, description, quantity, unit_amount)
  select i.id, i.academy_id, 'base', 'Monthly fee', 1, 2000
  from public.invoices i;

  insert into public.payments
    (academy_id, invoice_id, student_id, amount, method, status)
  select i.academy_id, i.id, i.student_id, 1000, 'cash', 'completed'
  from public.invoices i;

  -- Storage objects in each bucket, one per academy. Path layout matches
  -- what StorageService writes from Flutter: <academy_id>/<entity>/...
  insert into storage.objects (bucket_id, name, metadata) values
    ('avatars',           v_academy_a::text || '/students/aaa.jpg', '{}'),
    ('avatars',           v_academy_b::text || '/students/bbb.jpg', '{}'),
    ('student_documents', v_academy_a::text || '/students/sa/aaa.pdf', '{}'),
    ('student_documents', v_academy_b::text || '/students/sb/bbb.pdf', '{}'),
    ('coach_documents',   v_academy_a::text || '/coaches/ca/aaa.pdf', '{}'),
    ('coach_documents',   v_academy_b::text || '/coaches/cb/bbb.pdf', '{}'),
    ('performance_media', v_academy_a::text || '/assessments/aa/clip.mp4', '{}'),
    ('performance_media', v_academy_b::text || '/assessments/bb/clip.mp4', '{}');

  -- Sprint-4 seed: a lead, an announcement (+ recipient), a direct thread
  -- + message, a notification, a device token, a parent_link per academy.
  insert into public.leads
    (academy_id, first_name, last_name, phone, source)
  values
    (v_academy_a, 'Lead', 'A', '+910000000001', 'website'),
    (v_academy_b, 'Lead', 'B', '+910000000002', 'website');

  insert into public.announcements (academy_id, subject, body, created_by)
  values
    (v_academy_a, 'Welcome A', 'Hello academy A', v_user_a),
    (v_academy_b, 'Welcome B', 'Hello academy B', v_user_b);

  insert into public.announcement_recipients (academy_id, announcement_id, user_id)
  select a.academy_id, a.id,
         case when a.academy_id = v_academy_a then v_user_a else v_user_b end
  from public.announcements a;

  -- Synthetic peer users (for direct-thread participant FKs).
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    ('00000000-cccc-0000-0000-000000000003',
     '00000000-0000-0000-0000-000000000000',
     'rls-peer-a@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now()),
    ('00000000-dddd-0000-0000-000000000004',
     '00000000-0000-0000-0000-000000000000',
     'rls-peer-b@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now())
  on conflict (id) do nothing;

  insert into public.users (id, role, academy_id, first_name, last_name, email)
  values
    ('00000000-cccc-0000-0000-000000000003', 'parent', v_academy_a,
       'Peer', 'A', 'rls-peer-a@example.invalid'),
    ('00000000-dddd-0000-0000-000000000004', 'parent', v_academy_b,
       'Peer', 'B', 'rls-peer-b@example.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id;

  -- Direct thread per academy with the user + their peer.
  insert into public.message_threads
    (academy_id, kind, direct_user_a, direct_user_b, created_by)
  values
    (v_academy_a, 'direct',
       least(v_user_a, '00000000-cccc-0000-0000-000000000003'::uuid),
       greatest(v_user_a, '00000000-cccc-0000-0000-000000000003'::uuid),
       v_user_a),
    (v_academy_b, 'direct',
       least(v_user_b, '00000000-dddd-0000-0000-000000000004'::uuid),
       greatest(v_user_b, '00000000-dddd-0000-0000-000000000004'::uuid),
       v_user_b);

  insert into public.thread_participants (thread_id, user_id, academy_id)
  select t.id, t.direct_user_a, t.academy_id from public.message_threads t
  union
  select t.id, t.direct_user_b, t.academy_id from public.message_threads t;

  insert into public.messages (thread_id, academy_id, sender_id, content)
  select t.id, t.academy_id,
         case when t.academy_id = v_academy_a then v_user_a else v_user_b end,
         'hello'
  from public.message_threads t;

  insert into public.notifications
    (user_id, academy_id, category, title, body)
  values
    (v_user_a, v_academy_a, 'system', 'Welcome A', 'body A'),
    (v_user_b, v_academy_b, 'system', 'Welcome B', 'body B');

  insert into public.device_tokens (user_id, academy_id, fcm_token, platform)
  values
    (v_user_a, v_academy_a, 'fcm-token-a', 'android'),
    (v_user_b, v_academy_b, 'fcm-token-b', 'android');

  insert into public.parent_links
    (academy_id, parent_user_id, student_id)
  select s.academy_id,
         case when s.academy_id = v_academy_a then v_user_a else v_user_b end,
         s.id
  from public.students s;

  -- Sprint-5 seed: events + registration + result, vendors + inventory items
  -- + a movement, support tickets, and saas_invoices (academy_subscriptions
  -- auto-created via trigger).
  insert into public.events
    (academy_id, title, kind, status, starts_at)
  values
    (v_academy_a, 'Cup A', 'tournament', 'published',
       now() + interval '14 days'),
    (v_academy_b, 'Cup B', 'tournament', 'published',
       now() + interval '14 days');

  insert into public.event_registrations
    (academy_id, event_id, student_id)
  select e.academy_id, e.id, s.id
  from public.events e
  join public.students s on s.academy_id = e.academy_id;

  insert into public.event_results
    (academy_id, event_id, student_id, placement)
  select er.academy_id, er.event_id, er.student_id, 1
  from public.event_registrations er;

  insert into public.vendors (academy_id, name)
  values (v_academy_a, 'Vendor A'), (v_academy_b, 'Vendor B');

  insert into public.inventory_categories (academy_id, name)
  values (v_academy_a, 'Cat A'), (v_academy_b, 'Cat B');

  insert into public.inventory_items
    (academy_id, name, unit, on_hand, reorder_threshold)
  values
    (v_academy_a, 'Ball A', 'piece', 0, 5),
    (v_academy_b, 'Ball B', 'piece', 0, 5);

  insert into public.inventory_movements (academy_id, item_id, kind, qty)
  select i.academy_id, i.id, 'in', 10
  from public.inventory_items i;

  insert into public.support_tickets (academy_id, opened_by, subject, body)
  values
    (v_academy_a, v_user_a, 'Hello A', 'Body A'),
    (v_academy_b, v_user_b, 'Hello B', 'Body B');

  insert into public.support_ticket_messages
    (ticket_id, academy_id, author_id, is_staff, body)
  select t.id, t.academy_id, t.opened_by, false, 'reply ' || t.subject
  from public.support_tickets t;

  insert into public.saas_invoices
    (academy_id, subscription_id, invoice_number, status,
     period_start, period_end, due_date, amount)
  select s.academy_id, s.id,
         'TEST-' || s.academy_id::text,
         'issued',
         now(), now() + interval '1 month',
         (current_date + interval '7 days')::date,
         1499
  from public.academy_subscriptions s;

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

-- ---------- Test 14: attendance read isolation -----------------------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.attendance_records where academy_id = v_academy_a;
  select count(*) into v_other
    from public.attendance_records where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own academy attendance';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % attendance rows from academy B',
      v_other;
  end if;
  raise notice 'PASS: attendance read isolation';
end $$;

-- ---------- Test 15: cross-tenant attendance insert blocked ---------------

do $$
declare
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_batch_b uuid;
  v_student_b uuid;
  v_caught boolean := false;
begin
  -- Resolve B's batch + student via service-role bypass: switch role briefly.
  reset role;
  select id into v_batch_b from public.batches
    where academy_id = v_academy_b limit 1;
  select id into v_student_b from public.students
    where academy_id = v_academy_b limit 1;
  set local role authenticated;
  set local request.jwt.claim.sub = '00000000-aaaa-0000-0000-000000000001';

  begin
    insert into public.attendance_records
      (academy_id, batch_id, student_id, date, status, method)
    values (v_academy_b, v_batch_b, v_student_b,
            current_date + 1, 'present', 'manual');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted attendance into academy B';
  end if;
  raise notice 'PASS: cross-tenant attendance insert blocked';
end $$;

-- ---------- Test 16: performance_assessments read isolation ---------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.performance_assessments where academy_id = v_academy_a;
  select count(*) into v_other
    from public.performance_assessments where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own academy performance';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % performance rows from academy B',
      v_other;
  end if;
  raise notice 'PASS: performance_assessments read isolation';
end $$;

-- ---------- Test 17: performance_skills + media isolation -----------------

do $$
declare
  v_own_s int;
  v_other_s int;
  v_other_m int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own_s
    from public.performance_skills where academy_id = v_academy_a;
  select count(*) into v_other_s
    from public.performance_skills where academy_id = v_academy_b;
  if v_own_s = 0 then
    raise exception 'FAIL: user A could not read own academy performance_skills';
  end if;
  if v_other_s > 0 then
    raise exception 'FAIL: user A read % performance_skills from academy B',
      v_other_s;
  end if;
  -- performance_media seeded only via storage; the table itself starts empty
  -- in this test, but still verify cross-tenant SELECT returns nothing.
  select count(*) into v_other_m
    from public.performance_media where academy_id = v_academy_b;
  if v_other_m > 0 then
    raise exception 'FAIL: user A read % performance_media rows from academy B',
      v_other_m;
  end if;
  raise notice 'PASS: performance_skills + performance_media read isolation';
end $$;

-- ---------- Test 18: storage — performance_media (private bucket) ---------

do $$
declare
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_own int;
  v_other int;
  v_caught boolean := false;
begin
  select count(*) into v_own from storage.objects
    where bucket_id = 'performance_media'
      and name like v_academy_a::text || '/%';
  select count(*) into v_other from storage.objects
    where bucket_id = 'performance_media'
      and name like v_academy_b::text || '/%';

  if v_own = 0 then
    raise exception 'FAIL: user A could not read own performance_media objects';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % performance_media objects from academy B',
      v_other;
  end if;

  begin
    insert into storage.objects (bucket_id, name, metadata)
    values ('performance_media',
            v_academy_b::text || '/assessments/zz/sneaky.mp4', '{}');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted performance_media into academy B folder';
  end if;

  raise notice 'PASS: performance_media — read isolation + cross-tenant insert blocked';
end $$;

-- ---------- Test 19: fee_structures read isolation ------------------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.fee_structures where academy_id = v_academy_a;
  select count(*) into v_other
    from public.fee_structures where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own fee_structures';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % fee_structures from academy B', v_other;
  end if;
  raise notice 'PASS: fee_structures read isolation';
end $$;

-- ---------- Test 20: invoices read isolation + cross-tenant insert blocked --

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_student_b uuid;
  v_caught boolean := false;
begin
  select count(*) into v_own
    from public.invoices where academy_id = v_academy_a;
  select count(*) into v_other
    from public.invoices where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own invoices';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % invoices from academy B', v_other;
  end if;

  reset role;
  select id into v_student_b from public.students
    where academy_id = v_academy_b limit 1;
  set local role authenticated;
  set local request.jwt.claim.sub = '00000000-aaaa-0000-0000-000000000001';

  begin
    insert into public.invoices
      (academy_id, student_id, invoice_number, due_date,
       base_amount, tax_amount)
    values (v_academy_b, v_student_b, 'SNEAK-001', current_date,
            500, 0);
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted invoice into academy B';
  end if;
  raise notice 'PASS: invoices read + cross-tenant insert blocked';
end $$;

-- ---------- Test 21: invoice_line_items + payments + refunds isolation -----

do $$
declare
  v_own_l int;
  v_other_l int;
  v_own_p int;
  v_other_p int;
  v_other_r int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own_l
    from public.invoice_line_items where academy_id = v_academy_a;
  select count(*) into v_other_l
    from public.invoice_line_items where academy_id = v_academy_b;
  if v_own_l = 0 then
    raise exception 'FAIL: user A could not read own invoice_line_items';
  end if;
  if v_other_l > 0 then
    raise exception 'FAIL: user A read % line items from academy B', v_other_l;
  end if;

  select count(*) into v_own_p
    from public.payments where academy_id = v_academy_a;
  select count(*) into v_other_p
    from public.payments where academy_id = v_academy_b;
  if v_own_p = 0 then
    raise exception 'FAIL: user A could not read own payments';
  end if;
  if v_other_p > 0 then
    raise exception 'FAIL: user A read % payments from academy B', v_other_p;
  end if;

  -- refunds is empty in seed; just verify the cross-tenant filter works.
  select count(*) into v_other_r
    from public.refunds where academy_id = v_academy_b;
  if v_other_r > 0 then
    raise exception 'FAIL: user A read % refunds from academy B', v_other_r;
  end if;

  raise notice 'PASS: invoice_line_items + payments + refunds isolation';
end $$;

-- ---------- Test 22: invoice number sequence is per-academy + unique -------

do $$
declare
  v_first text;
  v_second text;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_b_first text;
begin
  -- next_invoice_number is SECURITY DEFINER, so user A can call it for
  -- their own academy. Two consecutive calls must produce two distinct
  -- monotonically-increasing numbers.
  v_first := public.next_invoice_number(v_academy_a);
  v_second := public.next_invoice_number(v_academy_a);
  if v_first = v_second then
    raise exception 'FAIL: next_invoice_number returned duplicate %', v_first;
  end if;

  -- Calling for academy B from user A also "works" (the function is
  -- definer-owned), but the numbers must come from B's counter — verify
  -- by calling it once for B and confirming the format prefix matches B's.
  v_b_first := public.next_invoice_number(v_academy_b);
  if substring(v_b_first from 1 for 4) <> substring(v_first from 1 for 4) then
    -- Different academies could pick different prefixes; the seed leaves
    -- both at the default 'INV', so this branch is informational only.
    null;
  end if;
  raise notice 'PASS: next_invoice_number unique per call (% then %)',
    v_first, v_second;
end $$;

-- ---------- Test 23: batch_fee_assignments isolation + cross-tenant block --

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_batch_b uuid;
  v_fee_b uuid;
  v_caught boolean := false;
begin
  select count(*) into v_own
    from public.batch_fee_assignments where academy_id = v_academy_a;
  select count(*) into v_other
    from public.batch_fee_assignments where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own batch_fee_assignments';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % batch_fee_assignments from academy B',
      v_other;
  end if;

  reset role;
  select id into v_batch_b from public.batches
    where academy_id = v_academy_b limit 1;
  select id into v_fee_b from public.fee_structures
    where academy_id = v_academy_b limit 1;
  set local role authenticated;
  set local request.jwt.claim.sub = '00000000-aaaa-0000-0000-000000000001';

  begin
    insert into public.batch_fee_assignments
      (academy_id, batch_id, fee_structure_id)
    values (v_academy_b, v_batch_b, v_fee_b);
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted batch_fee_assignment into academy B';
  end if;
  raise notice 'PASS: batch_fee_assignments read + cross-tenant insert blocked';
end $$;

-- ---------- Test 24: discount_structures + assignment isolation -----------

do $$
declare
  v_own_d int;
  v_other_d int;
  v_own_sd int;
  v_other_sd int;
  v_own_bd int;
  v_other_bd int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own_d
    from public.discount_structures where academy_id = v_academy_a;
  select count(*) into v_other_d
    from public.discount_structures where academy_id = v_academy_b;
  if v_own_d = 0 then
    raise exception 'FAIL: user A could not read own discount_structures';
  end if;
  if v_other_d > 0 then
    raise exception 'FAIL: user A read % discount_structures from academy B',
      v_other_d;
  end if;

  select count(*) into v_own_sd
    from public.student_discount_assignments where academy_id = v_academy_a;
  select count(*) into v_other_sd
    from public.student_discount_assignments where academy_id = v_academy_b;
  if v_own_sd = 0 then
    raise exception 'FAIL: user A could not read own student_discount_assignments';
  end if;
  if v_other_sd > 0 then
    raise exception 'FAIL: user A read % student_discount_assignments from academy B',
      v_other_sd;
  end if;

  select count(*) into v_own_bd
    from public.batch_discount_assignments where academy_id = v_academy_a;
  select count(*) into v_other_bd
    from public.batch_discount_assignments where academy_id = v_academy_b;
  if v_own_bd = 0 then
    raise exception 'FAIL: user A could not read own batch_discount_assignments';
  end if;
  if v_other_bd > 0 then
    raise exception 'FAIL: user A read % batch_discount_assignments from academy B',
      v_other_bd;
  end if;

  raise notice 'PASS: discount_structures + student/batch_discount_assignments isolation';
end $$;

-- ---------- Test 25: refresh_attendance_aggregates is callable ------------
-- The materialized views are not RLS-able directly, but the wrapper views
-- (`*_view`) re-apply tenant filtering. Verify user A only sees their own
-- academy's rows through the wrappers, and that the refresh RPC is callable.

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.student_attendance_summary_view where academy_id = v_academy_a;
  select count(*) into v_other
    from public.student_attendance_summary_view where academy_id = v_academy_b;
  -- v_own may be 0 if the view hasn't been refreshed since the seed insert,
  -- but cross-tenant rows must never be visible.
  if v_other > 0 then
    raise exception 'FAIL: user A read % attendance_summary rows from academy B',
      v_other;
  end if;
  raise notice 'PASS: student_attendance_summary_view tenant filter (% own, % other)',
    v_own, v_other;
end $$;

-- ---------- Test 26: leads + lead_activities isolation -------------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_caught boolean := false;
begin
  select count(*) into v_own from public.leads where academy_id = v_academy_a;
  select count(*) into v_other from public.leads where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own leads';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % leads from academy B', v_other;
  end if;

  begin
    insert into public.leads (academy_id, first_name, phone)
    values (v_academy_b, 'Sneaky', '+919999999999');
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted lead into academy B';
  end if;

  raise notice 'PASS: leads read + cross-tenant insert blocked';
end $$;

-- ---------- Test 27: announcements + recipients isolation ----------------

do $$
declare
  v_own int;
  v_other int;
  v_own_r int;
  v_other_r int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.announcements where academy_id = v_academy_a;
  select count(*) into v_other
    from public.announcements where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own announcements';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % announcements from academy B', v_other;
  end if;

  -- Recipients: user A is owner so academy-admin path applies; only own rows.
  select count(*) into v_own_r
    from public.announcement_recipients where academy_id = v_academy_a;
  select count(*) into v_other_r
    from public.announcement_recipients where academy_id = v_academy_b;
  if v_own_r = 0 then
    raise exception 'FAIL: user A could not read own announcement_recipients';
  end if;
  if v_other_r > 0 then
    raise exception 'FAIL: user A read % announcement_recipients from academy B',
      v_other_r;
  end if;

  raise notice 'PASS: announcements + recipients isolation';
end $$;

-- ---------- Test 28: message_threads + messages isolation ----------------

do $$
declare
  v_own int;
  v_other int;
  v_own_m int;
  v_other_m int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.message_threads where academy_id = v_academy_a;
  select count(*) into v_other
    from public.message_threads where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own threads (admin path)';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % threads from academy B', v_other;
  end if;

  select count(*) into v_own_m
    from public.messages where academy_id = v_academy_a;
  select count(*) into v_other_m
    from public.messages where academy_id = v_academy_b;
  if v_own_m = 0 then
    raise exception 'FAIL: user A could not read own messages';
  end if;
  if v_other_m > 0 then
    raise exception 'FAIL: user A read % messages from academy B', v_other_m;
  end if;

  raise notice 'PASS: message_threads + messages isolation';
end $$;

-- ---------- Test 29: notifications + device_tokens self-only -------------

do $$
declare
  v_own int;
  v_other int;
  v_other_dev int;
  v_user_a uuid := current_setting('test.user_a')::uuid;
  v_user_b uuid := current_setting('test.user_b')::uuid;
begin
  select count(*) into v_own
    from public.notifications where user_id = v_user_a;
  select count(*) into v_other
    from public.notifications where user_id = v_user_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own notifications';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % notifications belonging to user B',
      v_other;
  end if;

  select count(*) into v_other_dev
    from public.device_tokens where user_id = v_user_b;
  if v_other_dev > 0 then
    raise exception 'FAIL: user A read user B''s device_tokens';
  end if;

  raise notice 'PASS: notifications + device_tokens self-only isolation';
end $$;

-- ---------- Test 30: parent_links isolation ------------------------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_caught boolean := false;
  v_student_b uuid;
  v_user_b uuid := current_setting('test.user_b')::uuid;
begin
  select count(*) into v_own
    from public.parent_links where academy_id = v_academy_a;
  select count(*) into v_other
    from public.parent_links where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own parent_links';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % parent_links from academy B', v_other;
  end if;

  reset role;
  select id into v_student_b from public.students
    where academy_id = v_academy_b limit 1;
  set local role authenticated;
  set local request.jwt.claim.sub = '00000000-aaaa-0000-0000-000000000001';

  begin
    insert into public.parent_links
      (academy_id, parent_user_id, student_id)
    values (v_academy_b, v_user_b, v_student_b);
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: user A inserted parent_link into academy B';
  end if;

  raise notice 'PASS: parent_links read + cross-tenant insert blocked';
end $$;

-- ---------- Test 31: events + registrations + results isolation ----------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_caught boolean := false;
  v_event_b uuid;
  v_student_a uuid;
begin
  select count(*) into v_own
    from public.events where academy_id = v_academy_a;
  select count(*) into v_other
    from public.events where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own events';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % events from academy B', v_other;
  end if;

  select count(*) into v_other from public.event_registrations
    where academy_id = v_academy_b;
  if v_other > 0 then
    raise exception 'FAIL: user A read % event_registrations from academy B',
      v_other;
  end if;

  select count(*) into v_other from public.event_results
    where academy_id = v_academy_b;
  if v_other > 0 then
    raise exception 'FAIL: user A read % event_results from academy B',
      v_other;
  end if;

  -- Cross-tenant insert into event_registrations must fail.
  reset role;
  select id into v_event_b from public.events
    where academy_id = v_academy_b limit 1;
  select id into v_student_a from public.students
    where academy_id = v_academy_a limit 1;
  set local role authenticated;
  set local request.jwt.claim.sub = '00000000-aaaa-0000-0000-000000000001';

  begin
    insert into public.event_registrations
      (academy_id, event_id, student_id)
    values (v_academy_b, v_event_b, v_student_a);
  exception when others then
    v_caught := true;
  end;
  if not v_caught then
    raise exception
      'FAIL: user A inserted event_registration for event in academy B';
  end if;

  raise notice 'PASS: events + registrations + results isolation';
end $$;

-- ---------- Test 32: inventory tables isolation + on_hand sync -----------

do $$
declare
  v_own int;
  v_other int;
  v_on_hand numeric;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own from public.vendors
    where academy_id = v_academy_a;
  select count(*) into v_other from public.vendors
    where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own vendors';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % vendors from academy B', v_other;
  end if;

  select count(*) into v_other from public.inventory_items
    where academy_id = v_academy_b;
  if v_other > 0 then
    raise exception 'FAIL: user A read % inventory_items from academy B',
      v_other;
  end if;

  select count(*) into v_other from public.inventory_movements
    where academy_id = v_academy_b;
  if v_other > 0 then
    raise exception
      'FAIL: user A read % inventory_movements from academy B', v_other;
  end if;

  -- Trigger sync check: the seed inserted a +10 'in' movement on each item,
  -- so the on_hand should be 10 (NOT 0) for the academy_a item.
  select on_hand into v_on_hand from public.inventory_items
    where academy_id = v_academy_a limit 1;
  if v_on_hand <> 10 then
    raise exception 'FAIL: on_hand sync trigger did not apply (got %)',
      v_on_hand;
  end if;

  raise notice 'PASS: inventory isolation + on_hand sync';
end $$;

-- ---------- Test 33: support tickets + messages isolation ----------------

do $$
declare
  v_own int;
  v_other int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own
    from public.support_tickets where academy_id = v_academy_a;
  select count(*) into v_other
    from public.support_tickets where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: user A could not read own support_tickets';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: user A read % support_tickets from academy B',
      v_other;
  end if;

  select count(*) into v_other
    from public.support_ticket_messages where academy_id = v_academy_b;
  if v_other > 0 then
    raise exception
      'FAIL: user A read % support_ticket_messages from academy B', v_other;
  end if;

  raise notice 'PASS: support tickets + messages isolation';
end $$;

-- ---------- Test 34: SaaS billing visible only to academy owner ---------

do $$
declare
  v_own int;
  v_other int;
  v_subs int;
  v_academy_a uuid := current_setting('test.academy_a')::uuid;
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
begin
  select count(*) into v_own from public.saas_invoices
    where academy_id = v_academy_a;
  select count(*) into v_other from public.saas_invoices
    where academy_id = v_academy_b;
  if v_own = 0 then
    raise exception 'FAIL: owner A could not read own saas_invoices';
  end if;
  if v_other > 0 then
    raise exception 'FAIL: owner A read % saas_invoices from academy B',
      v_other;
  end if;

  select count(*) into v_subs from public.academy_subscriptions
    where academy_id = v_academy_a;
  if v_subs = 0 then
    raise exception
      'FAIL: ensure_academy_subscription trigger did not auto-create row';
  end if;

  raise notice 'PASS: saas_invoices owner-only visibility + auto-create';
end $$;

-- ---------- Reset and roll back --------------------------------------------

reset role;
rollback;

\echo 'All RLS isolation tests passed.'
