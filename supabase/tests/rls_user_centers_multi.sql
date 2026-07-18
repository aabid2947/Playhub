-- ============================================================================
-- Multi-center admins (20260614000000_user_centers_multi.sql).
--
-- Academy A1 with centers C1/C2/C3. center_admin `ca` has home center C1 and an
-- EXTRA grant to C2 via user_centers (NOT C3). `ca2` is a plain single-center
-- admin (home C1, no grants) to prove the old behaviour is unchanged.
-- Academy A2 (owner2 + center C4) proves cross-tenant isolation on user_centers.
--
-- Asserts:
--   • ca READS students/batches in C1 + C2, NOT C3.
--   • ca WRITE gates (can_admin_center_scope / can_provision_role) allow C1+C2,
--     deny C3; an actual student INSERT succeeds for C2 and is blocked for C3.
--   • current_user_in_center reflects C1+C2 true, C3 false.
--   • ca2 (no grants) sees/writes ONLY C1 — the single-center model is intact.
--   • ca cannot read or write A2's user_centers rows (tenant isolation).
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner  constant uuid := '00000000-1c00-0000-0000-000000000001';
  v_ca     constant uuid := '00000000-1c00-0000-0000-000000000002';
  v_ca2    constant uuid := '00000000-1c00-0000-0000-000000000003';
  v_owner2 constant uuid := '00000000-1c00-0000-0000-000000000004';
  v_a1 uuid; v_a2 uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid; v_c4 uuid;
  v_s1 uuid; v_s2 uuid; v_s3 uuid;
  v_b1 uuid; v_b2 uuid; v_b3 uuid;
  v_uc_a2 uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner,  '00000000-0000-0000-0000-000000000000', 'uc-owner@x.invalid',  'authenticated', 'authenticated', now(), now(), now()),
    (v_ca,     '00000000-0000-0000-0000-000000000000', 'uc-ca@x.invalid',     'authenticated', 'authenticated', now(), now(), now()),
    (v_ca2,    '00000000-0000-0000-0000-000000000000', 'uc-ca2@x.invalid',    'authenticated', 'authenticated', now(), now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'uc-owner2@x.invalid', 'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id) values ('UC Academy 1', v_owner)  returning id into v_a1;
  insert into public.academies (name, owner_id) values ('UC Academy 2', v_owner2) returning id into v_a2;

  insert into public.centers (academy_id, name) values (v_a1, 'C1') returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_a1, 'C2') returning id into v_c2;
  insert into public.centers (academy_id, name) values (v_a1, 'C3') returning id into v_c3;
  insert into public.centers (academy_id, name) values (v_a2, 'C4') returning id into v_c4;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner,  'academy_owner', v_a1, null, 'Owner',  'O',  'uc-owner@x.invalid'),
    (v_ca,     'center_admin',  v_a1, v_c1, 'CA',     'M',  'uc-ca@x.invalid'),
    (v_ca2,    'center_admin',  v_a1, v_c1, 'CA',     'S',  'uc-ca2@x.invalid'),
    (v_owner2, 'academy_owner', v_a2, null, 'Owner2', 'O',  'uc-owner2@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  -- ca's EXTRA grant: C2 (home C1 stays on users.center_id). C3 is NOT granted.
  insert into public.user_centers (academy_id, user_id, center_id)
  values (v_a1, v_ca, v_c2);

  -- A2's own grant — ca (A1) must never touch it.
  insert into public.user_centers (academy_id, user_id, center_id)
  values (v_a2, v_owner2, v_c4) returning id into v_uc_a2;

  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_a1, v_c1, 'Stu', 'C1', 'P') returning id into v_s1;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_a1, v_c2, 'Stu', 'C2', 'P') returning id into v_s2;
  insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
  values (v_a1, v_c3, 'Stu', 'C3', 'P') returning id into v_s3;

  insert into public.batches (academy_id, center_id, name) values (v_a1, v_c1, 'B C1') returning id into v_b1;
  insert into public.batches (academy_id, center_id, name) values (v_a1, v_c2, 'B C2') returning id into v_b2;
  insert into public.batches (academy_id, center_id, name) values (v_a1, v_c3, 'B C3') returning id into v_b3;

  perform set_config('uc.a1', v_a1::text, true);
  perform set_config('uc.a2', v_a2::text, true);
  perform set_config('uc.c1', v_c1::text, true);
  perform set_config('uc.c2', v_c2::text, true);
  perform set_config('uc.c3', v_c3::text, true);
  perform set_config('uc.c4', v_c4::text, true);
  perform set_config('uc.s1', v_s1::text, true);
  perform set_config('uc.s2', v_s2::text, true);
  perform set_config('uc.s3', v_s3::text, true);
  perform set_config('uc.b1', v_b1::text, true);
  perform set_config('uc.b2', v_b2::text, true);
  perform set_config('uc.b3', v_b3::text, true);
  perform set_config('uc.uc_a2', v_uc_a2::text, true);
end $$;

-- ---------- ca: multi-center (C1 + C2), NOT C3 ------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-1c00-0000-0000-000000000002';  -- ca

do $$
declare
  v1 int; v2 int; v3 int;
begin
  -- membership helper
  if not public.current_user_in_center(current_setting('uc.c1')::uuid)
     or not public.current_user_in_center(current_setting('uc.c2')::uuid)
     or public.current_user_in_center(current_setting('uc.c3')::uuid) then
    raise exception 'FAIL: current_user_in_center wrong (c1/c2 should be true, c3 false)';
  end if;

  -- READ students: C1 + C2 visible, C3 not.
  select count(*) into v1 from public.students where id = current_setting('uc.s1')::uuid;
  select count(*) into v2 from public.students where id = current_setting('uc.s2')::uuid;
  select count(*) into v3 from public.students where id = current_setting('uc.s3')::uuid;
  if v1 <> 1 or v2 <> 1 or v3 <> 0 then
    raise exception 'FAIL: students read not multi-center (c1=%, c2=%, c3=%)', v1, v2, v3;
  end if;

  -- READ batches: C1 + C2 visible, C3 not.
  select count(*) into v1 from public.batches where id = current_setting('uc.b1')::uuid;
  select count(*) into v2 from public.batches where id = current_setting('uc.b2')::uuid;
  select count(*) into v3 from public.batches where id = current_setting('uc.b3')::uuid;
  if v1 <> 1 or v2 <> 1 or v3 <> 0 then
    raise exception 'FAIL: batches read not multi-center (c1=%, c2=%, c3=%)', v1, v2, v3;
  end if;

  -- WRITE gates
  if not public.can_admin_center_scope(current_setting('uc.c2')::uuid)
     or public.can_admin_center_scope(current_setting('uc.c3')::uuid) then
    raise exception 'FAIL: can_admin_center_scope wrong (c2 true, c3 false)';
  end if;
  if not public.can_provision_role('coach', current_setting('uc.c2')::uuid)
     or public.can_provision_role('coach', current_setting('uc.c3')::uuid) then
    raise exception 'FAIL: can_provision_role wrong (c2 true, c3 false)';
  end if;

  raise notice 'PASS: ca reads + write-gates span C1+C2, exclude C3';
end $$;

-- Actual write: INSERT student into granted C2 succeeds; into C3 is blocked.
insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
values (current_setting('uc.a1')::uuid, current_setting('uc.c2')::uuid, 'New', 'InC2', 'P');

do $$
begin
  begin
    insert into public.students (academy_id, center_id, first_name, last_name, parent_name)
    values (current_setting('uc.a1')::uuid, current_setting('uc.c3')::uuid, 'New', 'InC3', 'P');
    raise exception 'FAIL: ca was able to INSERT a student into ungranted C3';
  exception
    when insufficient_privilege then null;  -- expected: RLS blocked the write
  end;
  raise notice 'PASS: ca INSERT allowed in C2, blocked in C3';
end $$;

-- user_centers tenant isolation: ca (A1) cannot see A2's grant nor write one.
do $$
declare v int;
begin
  select count(*) into v from public.user_centers where id = current_setting('uc.uc_a2')::uuid;
  if v <> 0 then raise exception 'FAIL: ca can read another academy''s user_centers row'; end if;

  begin
    insert into public.user_centers (academy_id, user_id, center_id)
    values (current_setting('uc.a1')::uuid, '00000000-1c00-0000-0000-000000000002',
            current_setting('uc.c3')::uuid);
    raise exception 'FAIL: center_admin was able to self-grant a center';
  exception
    when insufficient_privilege then null;  -- expected: only admin tier may grant
  end;
  raise notice 'PASS: user_centers isolation — ca cannot read A2 rows nor self-grant';
end $$;

-- ---------- ca2: single-center (home C1 only), unchanged behaviour ----------
set local request.jwt.claim.sub = '00000000-1c00-0000-0000-000000000003';  -- ca2

do $$
declare v1 int; v2 int;
begin
  if not public.current_user_in_center(current_setting('uc.c1')::uuid)
     or public.current_user_in_center(current_setting('uc.c2')::uuid) then
    raise exception 'FAIL: single-center ca2 leaked into C2';
  end if;

  select count(*) into v1 from public.students where id = current_setting('uc.s1')::uuid;
  select count(*) into v2 from public.students where id = current_setting('uc.s2')::uuid;
  if v1 <> 1 or v2 <> 0 then
    raise exception 'FAIL: ca2 not single-center scoped (c1=%, c2=%)', v1, v2;
  end if;
  raise notice 'PASS: ca2 single-center model intact (C1 only)';
end $$;

-- ---------- owner (A1): grants user_centers; admin tier can manage ----------
set local request.jwt.claim.sub = '00000000-1c00-0000-0000-000000000001';  -- owner

do $$
declare v int;
begin
  -- owner may grant ca2 a second center (defence-in-depth ladder allows admin tier).
  insert into public.user_centers (academy_id, user_id, center_id)
  values (current_setting('uc.a1')::uuid, '00000000-1c00-0000-0000-000000000003',
          current_setting('uc.c2')::uuid);
  select count(*) into v from public.user_centers
    where user_id = '00000000-1c00-0000-0000-000000000003'::uuid;
  if v <> 1 then raise exception 'FAIL: owner could not grant ca2 a center'; end if;
  raise notice 'PASS: admin tier can grant user_centers';
end $$;

reset role;
rollback;

\echo 'All user_centers multi-center tests passed.'
