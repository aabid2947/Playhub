-- ============================================================================
-- Phase 5 regression — center_admin READ isolation on the secondary lists
-- (20260607000500_center_read_isolation.sql).
--
-- One academy, centers C1/C2. center_admin ca1 in C1; a coach cc in C1 (to
-- prove non-center_admins are unaffected). One of each entity per center.
--
-- Asserts:
--   • center_admin (C1) sees own-center coaches/leads/items/events/batch_staff,
--     NOT the C2 ones.
--   • coach (non-center_admin) still sees coaches academy-wide (short-circuit).
--   • announcements: non-admin sees only ones delivered to them; admin sees all.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner constant uuid := '00000000-1100-0000-0000-000000000001';
  v_ca1   constant uuid := '00000000-1100-0000-0000-000000000002';
  v_cc    constant uuid := '00000000-1100-0000-0000-000000000003';
  v_academy uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_coach1 uuid; v_coach2 uuid;
  v_lead1 uuid;  v_lead2 uuid;
  v_item1 uuid;  v_item2 uuid;
  v_event1 uuid; v_event2 uuid;
  v_b1 uuid;     v_b2 uuid;
  v_annA uuid;   v_annB uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner, '00000000-0000-0000-0000-000000000000', 'cri-owner@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_ca1,   '00000000-0000-0000-0000-000000000000', 'cri-ca1@x.invalid',   'authenticated', 'authenticated', now(), now(), now()),
    (v_cc,    '00000000-0000-0000-0000-000000000000', 'cri-cc@x.invalid',    'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id) values ('Read-Iso Academy', v_owner)
  returning id into v_academy;
  insert into public.centers (academy_id, name) values (v_academy, 'C1') returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_academy, 'C2') returning id into v_c2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner, 'academy_owner', v_academy, null, 'Owner', 'O', 'cri-owner@x.invalid'),
    (v_ca1,   'center_admin',  v_academy, v_c1, 'CA', '1', 'cri-ca1@x.invalid'),
    (v_cc,    'coach',         v_academy, v_c1, 'Co', 'X', 'cri-cc@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id, center_id = excluded.center_id;

  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c1, 'Coach', 'C1') returning id into v_coach1;
  insert into public.coaches (academy_id, center_id, first_name, last_name)
  values (v_academy, v_c2, 'Coach', 'C2') returning id into v_coach2;

  insert into public.leads (academy_id, first_name, phone, preferred_center_id)
  values (v_academy, 'Lead', '+919000000001', v_c1) returning id into v_lead1;
  insert into public.leads (academy_id, first_name, phone, preferred_center_id)
  values (v_academy, 'Lead', '+919000000002', v_c2) returning id into v_lead2;

  insert into public.inventory_items (academy_id, center_id, name)
  values (v_academy, v_c1, 'Item C1') returning id into v_item1;
  insert into public.inventory_items (academy_id, center_id, name)
  values (v_academy, v_c2, 'Item C2') returning id into v_item2;

  insert into public.events (academy_id, center_id, title, starts_at, status)
  values (v_academy, v_c1, 'Event C1', now(), 'published') returning id into v_event1;
  insert into public.events (academy_id, center_id, title, starts_at, status)
  values (v_academy, v_c2, 'Event C2', now(), 'published') returning id into v_event2;

  insert into public.batches (academy_id, center_id, name)
  values (v_academy, v_c1, 'B C1') returning id into v_b1;
  insert into public.batches (academy_id, center_id, name)
  values (v_academy, v_c2, 'B C2') returning id into v_b2;

  insert into public.batch_staff (academy_id, batch_id, user_id, role)
  values (v_academy, v_b1, v_cc, 'trainer'),
         (v_academy, v_b2, v_cc, 'trainer');

  insert into public.announcements (academy_id, subject, body, created_by)
  values (v_academy, 'A', 'delivered to ca1', v_owner) returning id into v_annA;
  insert into public.announcements (academy_id, subject, body, created_by)
  values (v_academy, 'B', 'not delivered to ca1', v_owner) returning id into v_annB;
  insert into public.announcement_recipients (academy_id, announcement_id, user_id)
  values (v_academy, v_annA, v_ca1);

  perform set_config('cri.academy', v_academy::text, true);
  perform set_config('cri.coach1', v_coach1::text, true);
  perform set_config('cri.coach2', v_coach2::text, true);
  perform set_config('cri.lead1', v_lead1::text, true);
  perform set_config('cri.lead2', v_lead2::text, true);
  perform set_config('cri.item1', v_item1::text, true);
  perform set_config('cri.item2', v_item2::text, true);
  perform set_config('cri.event1', v_event1::text, true);
  perform set_config('cri.event2', v_event2::text, true);
  perform set_config('cri.b1', v_b1::text, true);
  perform set_config('cri.b2', v_b2::text, true);
  perform set_config('cri.annA', v_annA::text, true);
  perform set_config('cri.annB', v_annB::text, true);
end $$;

-- ---------- center_admin (C1): own-center secondary lists only --------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-1100-0000-0000-000000000002';  -- ca1

do $$
declare
  v_ok int; v_bad int;
begin
  select count(*) into v_ok  from public.coaches where id = current_setting('cri.coach1')::uuid;
  select count(*) into v_bad from public.coaches where id = current_setting('cri.coach2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: coaches not center-scoped (own=%, other=%)', v_ok, v_bad; end if;

  select count(*) into v_ok  from public.leads where id = current_setting('cri.lead1')::uuid;
  select count(*) into v_bad from public.leads where id = current_setting('cri.lead2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: leads not center-scoped'; end if;

  select count(*) into v_ok  from public.inventory_items where id = current_setting('cri.item1')::uuid;
  select count(*) into v_bad from public.inventory_items where id = current_setting('cri.item2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: inventory_items not center-scoped'; end if;

  select count(*) into v_ok  from public.events where id = current_setting('cri.event1')::uuid;
  select count(*) into v_bad from public.events where id = current_setting('cri.event2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: events not center-scoped'; end if;

  select count(*) into v_ok  from public.batch_staff where batch_id = current_setting('cri.b1')::uuid;
  select count(*) into v_bad from public.batch_staff where batch_id = current_setting('cri.b2')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: batch_staff not center-scoped'; end if;

  -- Announcements: only the one delivered to ca1.
  select count(*) into v_ok  from public.announcements where id = current_setting('cri.annA')::uuid;
  select count(*) into v_bad from public.announcements where id = current_setting('cri.annB')::uuid;
  if v_ok <> 1 or v_bad <> 0 then raise exception 'FAIL: announcements not delivery-scoped (A=%, B=%)', v_ok, v_bad; end if;

  raise notice 'PASS: center_admin — secondary lists + announcements scoped';
end $$;

-- ---------- coach (non-center_admin): coaches still academy-wide ------------

set local request.jwt.claim.sub = '00000000-1100-0000-0000-000000000003';  -- cc

do $$
declare
  v_c1 int; v_c2 int;
begin
  select count(*) into v_c1 from public.coaches where id = current_setting('cri.coach1')::uuid;
  select count(*) into v_c2 from public.coaches where id = current_setting('cri.coach2')::uuid;
  if v_c1 <> 1 or v_c2 <> 1 then
    raise exception 'FAIL: coach should see both coaches academy-wide (c1=%, c2=%)', v_c1, v_c2;
  end if;
  raise notice 'PASS: non-center_admin unaffected (academy-wide coaches)';
end $$;

-- ---------- owner: sees all + all announcements -----------------------------

set local request.jwt.claim.sub = '00000000-1100-0000-0000-000000000001';  -- owner

do $$
declare
  v_ann int; v_coaches int;
begin
  select count(*) into v_ann from public.announcements
    where academy_id = current_setting('cri.academy')::uuid;
  if v_ann < 2 then raise exception 'FAIL: owner cannot see all announcements'; end if;

  select count(*) into v_coaches from public.coaches
    where academy_id = current_setting('cri.academy')::uuid;
  if v_coaches < 2 then raise exception 'FAIL: owner cannot see all coaches'; end if;
  raise notice 'PASS: owner — academy-wide reads intact';
end $$;

reset role;
rollback;

\echo 'All center read-isolation tests passed.'
