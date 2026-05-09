-- ============================================================================
-- Sprint 5 — Inventory: equipment, kits, consumables.
--
-- Tables:
--   vendors              — suppliers
--   inventory_categories — top-level grouping (Cricket, Football, Apparel, …)
--   inventory_items      — SKU-level row with on-hand qty + reorder threshold
--   inventory_movements  — append-only ledger; +qty in, -qty out
--
-- on_hand is denormalized on inventory_items and kept in sync by an after-
-- insert trigger on inventory_movements (update of movements is forbidden;
-- mistakes are corrected by issuing a compensating movement).
-- low_stock = (on_hand <= reorder_threshold and reorder_threshold > 0).
-- ============================================================================

create table public.vendors (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  name text not null,
  contact_name text,
  email text,
  phone text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_vendors_academy on public.vendors(academy_id);

create trigger trg_vendors_updated before update on public.vendors
  for each row execute function public.set_updated_at();

create table public.inventory_categories (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  unique (academy_id, name)
);

create index idx_inv_categories_academy on public.inventory_categories(academy_id);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  category_id uuid references public.inventory_categories(id) on delete set null,
  center_id uuid references public.centers(id) on delete set null,
  vendor_id uuid references public.vendors(id) on delete set null,

  sku text,
  name text not null,
  description text,
  unit text not null default 'piece',  -- piece, pair, set, kg, …
  unit_cost numeric(10, 2) not null default 0 check (unit_cost >= 0),

  on_hand numeric(12, 2) not null default 0,
  reorder_threshold numeric(12, 2) not null default 0
    check (reorder_threshold >= 0),

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (academy_id, sku)
);

create index idx_inv_items_academy on public.inventory_items(academy_id);
create index idx_inv_items_category on public.inventory_items(category_id);
create index idx_inv_items_low_stock
  on public.inventory_items(academy_id)
  where reorder_threshold > 0 and on_hand <= reorder_threshold;

create trigger trg_inv_items_updated before update on public.inventory_items
  for each row execute function public.set_updated_at();

-- ============================================================================
-- inventory_movements — append-only ledger.
--   kind = 'in'         (purchase / restock)
--        | 'out'        (issue to coach / student)
--        | 'adjustment' (count correction; signed)
--        | 'return'     (returned to stock)
-- qty is signed: 'in' / 'return' positive, 'out' negative; 'adjustment' either.
-- The trigger validates the sign per kind to keep the ledger sane.
-- ============================================================================

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  item_id uuid not null references public.inventory_items(id) on delete cascade,

  kind text not null check (kind in ('in', 'out', 'adjustment', 'return')),
  qty numeric(12, 2) not null check (qty <> 0),

  -- Optional links: who is this for / from?
  student_id uuid references public.students(id) on delete set null,
  coach_id uuid references public.coaches(id) on delete set null,
  vendor_id uuid references public.vendors(id) on delete set null,
  unit_cost numeric(10, 2),
  reference text,                        -- PO #, invoice #, etc.
  notes text,

  performed_by uuid references public.users(id) on delete set null,
  performed_at timestamptz not null default now()
);

create index idx_inv_movements_item on public.inventory_movements(item_id, performed_at desc);
create index idx_inv_movements_academy on public.inventory_movements(academy_id, performed_at desc);
create index idx_inv_movements_student on public.inventory_movements(student_id);
create index idx_inv_movements_coach on public.inventory_movements(coach_id);

-- ============================================================================
-- Sign validation + on_hand sync.
-- ============================================================================

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
  -- adjustment may be either sign; nothing to enforce.
  return new;
end;
$$;

create trigger trg_inv_movement_validate
  before insert on public.inventory_movements
  for each row execute function public.validate_inventory_movement();

create or replace function public.sync_item_on_hand()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.inventory_items
    set on_hand = on_hand + new.qty
    where id = new.item_id;
  return new;
end;
$$;

create trigger trg_inv_movement_apply
  after insert on public.inventory_movements
  for each row execute function public.sync_item_on_hand();

-- Inventory movements are append-only — block update / delete from the app.

-- ============================================================================
-- RLS — academy-scoped, admin-or-higher writes. Coaches can issue/return
-- (i.e. insert into inventory_movements) but cannot edit items or vendors.
-- ============================================================================

alter table public.vendors              enable row level security;
alter table public.inventory_categories enable row level security;
alter table public.inventory_items      enable row level security;
alter table public.inventory_movements  enable row level security;

-- vendors --------------------------------------------------------------------
create policy vendors_academy_read on public.vendors
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
    )
  );

create policy vendors_admin_insert on public.vendors
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy vendors_admin_update on public.vendors
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy vendors_admin_delete on public.vendors
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- categories -----------------------------------------------------------------
create policy inv_cats_academy_read on public.inventory_categories
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
    )
  );

create policy inv_cats_admin_insert on public.inventory_categories
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy inv_cats_admin_update on public.inventory_categories
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy inv_cats_admin_delete on public.inventory_categories
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- items ----------------------------------------------------------------------
create policy inv_items_academy_read on public.inventory_items
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
    )
  );

create policy inv_items_admin_insert on public.inventory_items
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy inv_items_admin_update on public.inventory_items
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy inv_items_admin_delete on public.inventory_items
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- movements ------------------------------------------------------------------
create policy inv_moves_academy_read on public.inventory_movements
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
    )
  );

-- Coaches/head_coach/center_admin can issue/return; admin-or-higher full.
create policy inv_moves_staff_insert on public.inventory_movements
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin', 'head_coach', 'coach', 'trainer'
      )
    )
  );

-- No update/delete policies — ledger is append-only at the app layer.

-- Audit hooks ----------------------------------------------------------------
create trigger trg_audit_vendors
  after insert or update or delete on public.vendors
  for each row execute function public.write_audit_log();

create trigger trg_audit_inventory_categories
  after insert or update or delete on public.inventory_categories
  for each row execute function public.write_audit_log();

create trigger trg_audit_inventory_items
  after insert or update or delete on public.inventory_items
  for each row execute function public.write_audit_log();

create trigger trg_audit_inventory_movements
  after insert or update or delete on public.inventory_movements
  for each row execute function public.write_audit_log();
