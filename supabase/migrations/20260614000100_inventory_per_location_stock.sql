-- ============================================================================
-- Per-location inventory stock + inter-location transfers (HO ↔ Center,
-- Center ↔ Center). [Issue #7]
--
-- Until now an inventory item had ONE `center_id` and ONE `on_hand` number — a
-- single stock pool. The academy physically moves equipment between the head
-- office (HO) and its centers and needs to know "how much is where", so stock
-- becomes PER-LOCATION:
--
--   • New `inventory_stock(item_id, center_id, on_hand)` = the balance of an
--     item at one location. `center_id IS NULL` = the HO / academy pool.
--   • `inventory_movements` gains `center_id` (the location the entry affects)
--     and `to_center_id` (transfer destination), plus a new `kind = 'transfer'`.
--   • A transfer is ONE movement (qty > 0): the sync trigger subtracts qty from
--     the source balance and adds it to the destination — the item TOTAL is
--     unchanged. Purchase/Sale/Return/Adjust still net the item total, now also
--     posting to the affected location's balance.
--   • `inventory_items.on_hand` is kept as the academy-wide TOTAL (sum of all
--     location balances), so the list / low-stock / reports keep working.
--
-- Convention: a catalog item meant to live at several centers should be HO-level
-- (`inventory_items.center_id IS NULL`) so every center_admin can see it (the
-- existing item RLS), with per-center quantities tracked in inventory_stock.
--
-- Balance writes happen ONLY through the SECURITY DEFINER sync trigger, so
-- inventory_stock has a read policy but no client write policy (RLS deny).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. inventory_stock — per item, per location balance.
-- ----------------------------------------------------------------------------
create table public.inventory_stock (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  item_id uuid not null references public.inventory_items(id) on delete cascade,
  center_id uuid references public.centers(id) on delete cascade,  -- null = HO
  on_hand numeric(12, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- One balance per (item, location). NULL center is the single HO balance, so it
-- needs its own partial unique index (NULLs are distinct under a plain unique).
create unique index uq_inventory_stock_item_center
  on public.inventory_stock(item_id, center_id) where center_id is not null;
create unique index uq_inventory_stock_item_ho
  on public.inventory_stock(item_id) where center_id is null;
create index idx_inventory_stock_item    on public.inventory_stock(item_id);
create index idx_inventory_stock_center  on public.inventory_stock(center_id);
create index idx_inventory_stock_academy on public.inventory_stock(academy_id);

create trigger trg_inventory_stock_updated before update on public.inventory_stock
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2. inventory_movements — location of the entry + transfer destination + the
--    new 'transfer' kind.
-- ----------------------------------------------------------------------------
alter table public.inventory_movements
  add column center_id    uuid references public.centers(id) on delete set null,
  add column to_center_id uuid references public.centers(id) on delete set null;

alter table public.inventory_movements
  drop constraint inventory_movements_kind_check;
alter table public.inventory_movements
  add constraint inventory_movements_kind_check
  check (kind in ('in', 'out', 'adjustment', 'return', 'transfer'));

create index idx_inv_movements_center on public.inventory_movements(center_id);

-- ----------------------------------------------------------------------------
-- 3. Backfill: seed each item's current on_hand as its home-location balance,
--    and stamp historical movements with the item's home center for a
--    consistent ledger. (Balances come straight from on_hand, so this does not
--    recompute anything — the trigger below only fires on NEW movements.)
-- ----------------------------------------------------------------------------
insert into public.inventory_stock (academy_id, item_id, center_id, on_hand)
  select academy_id, id, center_id, on_hand
  from public.inventory_items;

update public.inventory_movements m
  set center_id = i.center_id
  from public.inventory_items i
  where m.item_id = i.id and m.center_id is null;

-- ----------------------------------------------------------------------------
-- 4. Balance delta helper — upsert-by-location, NULL-center safe.
--    SECURITY DEFINER: called only from the sync trigger (also definer), never
--    by clients, so it isn't granted to authenticated.
-- ----------------------------------------------------------------------------
create or replace function public.apply_inventory_stock_delta(
  p_academy_id uuid,
  p_item_id uuid,
  p_center_id uuid,
  p_delta numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.inventory_stock
    set on_hand = on_hand + p_delta
    where item_id = p_item_id
      and center_id is not distinct from p_center_id;
  if not found then
    insert into public.inventory_stock (academy_id, item_id, center_id, on_hand)
    values (p_academy_id, p_item_id, p_center_id, p_delta);
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. Validate — extend the sign rules to cover transfers.
-- ----------------------------------------------------------------------------
create or replace function public.validate_inventory_movement()
returns trigger
language plpgsql
as $$
begin
  if new.kind = 'in' and new.qty <= 0 then
    raise exception 'inventory_movements: ''in'' requires qty > 0 (got %)', new.qty;
  end if;
  if new.kind = 'return' and new.qty <= 0 then
    raise exception 'inventory_movements: ''return'' requires qty > 0 (got %)', new.qty;
  end if;
  if new.kind = 'out' and new.qty >= 0 then
    raise exception 'inventory_movements: ''out'' requires qty < 0 (got %)', new.qty;
  end if;
  if new.kind = 'transfer' then
    if new.qty <= 0 then
      raise exception 'inventory_movements: ''transfer'' requires qty > 0 (got %)', new.qty;
    end if;
    if new.center_id is not distinct from new.to_center_id then
      raise exception 'inventory_movements: transfer source and destination must differ';
    end if;
  elsif new.to_center_id is not null then
    raise exception 'inventory_movements: only transfers may set to_center_id (kind %)', new.kind;
  end if;
  -- adjustment may be either sign; nothing else to enforce.
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. Sync — post to per-location balances; transfers move between locations and
--    leave the item total unchanged, everything else nets the total too.
-- ----------------------------------------------------------------------------
create or replace function public.sync_item_on_hand()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.kind = 'transfer' then
    -- qty > 0: out of source, into destination; item total is unchanged.
    perform public.apply_inventory_stock_delta(
      new.academy_id, new.item_id, new.center_id, -new.qty);
    perform public.apply_inventory_stock_delta(
      new.academy_id, new.item_id, new.to_center_id, new.qty);
  else
    -- new.qty is already signed (in/return + , out - , adjustment either).
    perform public.apply_inventory_stock_delta(
      new.academy_id, new.item_id, new.center_id, new.qty);
    update public.inventory_items
      set on_hand = on_hand + new.qty
      where id = new.item_id;
  end if;
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. RLS — read-only for clients (balances are trigger-maintained). center_admin
--    sees HO (null) + its own centers via center_admin_sees_center (which now
--    spans every granted center, per 20260614000000). No write policies: the
--    SECURITY DEFINER sync trigger is the only writer.
-- ----------------------------------------------------------------------------
alter table public.inventory_stock enable row level security;

create policy inventory_stock_read on public.inventory_stock
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
      and public.center_admin_sees_center(center_id)
    )
  );

-- NOTE: movement INSERT stays governed by the existing inv_moves_staff_insert
-- (staff + academy match). Tightening WHO may transfer FROM/TO which location
-- (e.g. a center_admin only moving stock involving a center they manage) is a
-- deliberate follow-up — it must handle the HO (null-center) case so admins
-- aren't locked out, and isn't a tenant-isolation boundary (academy_id is).
