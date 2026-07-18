-- ============================================================================
-- Per-location inventory stock + transfers (20260614000100).
--
-- Academy A1 with centers C1/C2 and an HO-level catalog item. Drives a sequence
-- of movements as the owner and checks per-location balances + the item total.
-- A2 (separate academy) proves cross-tenant read isolation; ca (center_admin in
-- C1) proves the read scope (own center + HO, not C2).
--
-- Balances:
--   in +100 @ HO            → HO 100,                total 100
--   transfer 30 HO→C1       → HO 70,  C1 30,         total 100 (unchanged)
--   transfer 10 C1→C2       → HO 70,  C1 20,  C2 10, total 100 (unchanged)
--   out -5 @ C2 (sale)      → HO 70,  C1 20,  C2 5,  total 95
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_owner  constant uuid := '00000000-1e00-0000-0000-000000000001';
  v_ca     constant uuid := '00000000-1e00-0000-0000-000000000002';
  v_owner2 constant uuid := '00000000-1e00-0000-0000-000000000003';
  v_a1 uuid; v_a2 uuid;
  v_c1 uuid; v_c2 uuid;
  v_item uuid; v_item2 uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_owner,  '00000000-0000-0000-0000-000000000000', 'inv-owner@x.invalid',  'authenticated', 'authenticated', now(), now(), now()),
    (v_ca,     '00000000-0000-0000-0000-000000000000', 'inv-ca@x.invalid',     'authenticated', 'authenticated', now(), now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'inv-owner2@x.invalid', 'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id) values ('Inv Academy 1', v_owner)  returning id into v_a1;
  insert into public.academies (name, owner_id) values ('Inv Academy 2', v_owner2) returning id into v_a2;
  insert into public.centers (academy_id, name) values (v_a1, 'C1') returning id into v_c1;
  insert into public.centers (academy_id, name) values (v_a1, 'C2') returning id into v_c2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_owner,  'academy_owner', v_a1, null, 'Owner', 'O', 'inv-owner@x.invalid'),
    (v_ca,     'center_admin',  v_a1, v_c1, 'CA', '1', 'inv-ca@x.invalid'),
    (v_owner2, 'academy_owner', v_a2, null, 'Own2', 'O', 'inv-owner2@x.invalid')
  on conflict (id) do update set role = excluded.role,
    academy_id = excluded.academy_id, center_id = excluded.center_id;

  -- HO-level catalog item (center_id null) so it's academy-wide.
  insert into public.inventory_items (academy_id, name, unit, on_hand)
  values (v_a1, 'Football', 'piece', 0) returning id into v_item;
  -- A2 item for isolation.
  insert into public.inventory_items (academy_id, name, unit, on_hand)
  values (v_a2, 'Bat', 'piece', 0) returning id into v_item2;

  perform set_config('inv.a1', v_a1::text, true);
  perform set_config('inv.c1', v_c1::text, true);
  perform set_config('inv.c2', v_c2::text, true);
  perform set_config('inv.item', v_item::text, true);
  perform set_config('inv.item2', v_item2::text, true);
end $$;

-- ---------- owner records movements (staff insert) --------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-1e00-0000-0000-000000000001';  -- owner

-- in +100 @ HO
insert into public.inventory_movements (academy_id, item_id, kind, qty, center_id)
values (current_setting('inv.a1')::uuid, current_setting('inv.item')::uuid, 'in', 100, null);
-- transfer 30 HO→C1
insert into public.inventory_movements (academy_id, item_id, kind, qty, center_id, to_center_id)
values (current_setting('inv.a1')::uuid, current_setting('inv.item')::uuid, 'transfer', 30, null, current_setting('inv.c1')::uuid);
-- transfer 10 C1→C2
insert into public.inventory_movements (academy_id, item_id, kind, qty, center_id, to_center_id)
values (current_setting('inv.a1')::uuid, current_setting('inv.item')::uuid, 'transfer', 10, current_setting('inv.c1')::uuid, current_setting('inv.c2')::uuid);
-- out -5 @ C2 (sale)
insert into public.inventory_movements (academy_id, item_id, kind, qty, center_id)
values (current_setting('inv.a1')::uuid, current_setting('inv.item')::uuid, 'out', -5, current_setting('inv.c2')::uuid);

do $$
declare
  v_ho numeric; v_c1 numeric; v_c2 numeric; v_total numeric;
begin
  select on_hand into v_ho from public.inventory_stock
    where item_id = current_setting('inv.item')::uuid and center_id is null;
  select on_hand into v_c1 from public.inventory_stock
    where item_id = current_setting('inv.item')::uuid and center_id = current_setting('inv.c1')::uuid;
  select on_hand into v_c2 from public.inventory_stock
    where item_id = current_setting('inv.item')::uuid and center_id = current_setting('inv.c2')::uuid;
  select on_hand into v_total from public.inventory_items
    where id = current_setting('inv.item')::uuid;

  if v_ho <> 70 then raise exception 'FAIL: HO balance = % (want 70)', v_ho; end if;
  if v_c1 <> 20 then raise exception 'FAIL: C1 balance = % (want 20)', v_c1; end if;
  if v_c2 <> 5  then raise exception 'FAIL: C2 balance = % (want 5)', v_c2; end if;
  if v_total <> 95 then raise exception 'FAIL: item total = % (want 95)', v_total; end if;
  raise notice 'PASS: per-location balances + total correct (HO 70, C1 20, C2 5, total 95)';
end $$;

-- ---------- validate guards -------------------------------------------------
do $$
begin
  -- transfer to same location must fail
  begin
    insert into public.inventory_movements (academy_id, item_id, kind, qty, center_id, to_center_id)
    values (current_setting('inv.a1')::uuid, current_setting('inv.item')::uuid, 'transfer', 1,
            current_setting('inv.c1')::uuid, current_setting('inv.c1')::uuid);
    raise exception 'FAIL: transfer to same location was allowed';
  exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;  -- re-raise our own assert
  end;

  -- non-transfer setting to_center_id must fail
  begin
    insert into public.inventory_movements (academy_id, item_id, kind, qty, center_id, to_center_id)
    values (current_setting('inv.a1')::uuid, current_setting('inv.item')::uuid, 'in', 1,
            null, current_setting('inv.c1')::uuid);
    raise exception 'FAIL: non-transfer with to_center_id was allowed';
  exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  raise notice 'PASS: transfer validation guards';
end $$;

-- ---------- center_admin read scope: own center + HO, not C2 ----------------
set local request.jwt.claim.sub = '00000000-1e00-0000-0000-000000000002';  -- ca (C1)

do $$
declare v_ho int; v_c1 int; v_c2 int;
begin
  select count(*) into v_ho from public.inventory_stock
    where item_id = current_setting('inv.item')::uuid and center_id is null;
  select count(*) into v_c1 from public.inventory_stock
    where item_id = current_setting('inv.item')::uuid and center_id = current_setting('inv.c1')::uuid;
  select count(*) into v_c2 from public.inventory_stock
    where item_id = current_setting('inv.item')::uuid and center_id = current_setting('inv.c2')::uuid;
  if v_ho <> 1 or v_c1 <> 1 or v_c2 <> 0 then
    raise exception 'FAIL: center_admin stock scope wrong (HO=%, C1=%, C2=%)', v_ho, v_c1, v_c2;
  end if;
  raise notice 'PASS: center_admin sees HO + own center balances, not C2';
end $$;

-- ---------- cross-tenant isolation ------------------------------------------
set local request.jwt.claim.sub = '00000000-1e00-0000-0000-000000000003';  -- owner2 (A2)

do $$
declare v int;
begin
  select count(*) into v from public.inventory_stock
    where item_id = current_setting('inv.item')::uuid;  -- A1's item
  if v <> 0 then raise exception 'FAIL: A2 owner can read A1 inventory_stock'; end if;
  raise notice 'PASS: inventory_stock tenant-isolated';
end $$;

reset role;
rollback;

\echo 'All per-location inventory stock tests passed.'
