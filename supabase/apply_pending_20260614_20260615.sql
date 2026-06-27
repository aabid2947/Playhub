-- ============================================================================
-- COMBINED MIGRATIONS — apply since commit 721ed5d (2026-06-10)
-- Run once in the Supabase SQL editor. Wrapped in a single transaction:
-- if anything fails, NOTHING is applied (all-or-nothing).
--
-- Order (do not reorder — later sections depend on earlier ones):
--   1. 20260614000000_user_centers_multi
--   2. 20260614000100_inventory_per_location_stock
--   3. 20260614000200_support_ticket_number
--   4. 20260614000300_support_center_admin_raise
--   5. 20260614000400_academy_custom_sports
--   6. 20260614000500_signup_default_owner          <-- the signup-as-owner fix
--   7. 20260615000000_academy_payment_gateways
--   8. 20260615000100_paytm_payments                <-- depends on #7
--
-- NOTE: if your DB already has SOME of these, a `create table ...` will error
-- on "already exists" and the whole transaction rolls back. In that case use
-- `supabase db push` instead (applies only what's missing).
-- ============================================================================

begin;


-- ############################################################################
-- ## SECTION 1/8 : 20260614000000_user_centers_multi.sql
-- ############################################################################

-- ============================================================================
-- Multi-center admins — a center_admin (or any center-scoped staffer) may now
-- be assigned to MORE THAN ONE center.
--
-- Background: until now `users.center_id` was a single FK and every center
-- gate compared `row.center_id = current_user_center_id()`. The client needs
-- one center_admin to manage several centers (e.g. JP Nagar + Satyapura +
-- Arativeli in Bangalore).
--
-- Design (minimal-ripple, RLS stays the gate — invariant #1/#2):
--   • New `user_centers` join table = the EXTRA centers granted to a user.
--     `users.center_id` is kept as the user's PRIMARY/home center (shown in UI,
--     used as the form default); the join table holds the additional grants.
--   • New membership helper `current_user_in_center(center_id)` returns true
--     when center_id is the caller's home center OR appears in user_centers.
--     For a user with NO extra grants this is byte-identical to the old
--     `= current_user_center_id()` check, so single-center roles
--     (head_coach / coach with no grants) are completely unaffected.
--   • Every center-equality check inside the existing scope helpers is swapped
--     for current_user_in_center(...). The RLS POLICIES are untouched — they
--     call the helpers, so read/write across all granted centers "just works"
--     (students, batches, attendance, performance, finance, coaches, leads,
--     inventory, events, provisioning, announcement targeting).
--
-- Who may grant centers: admin tier only (academy_owner / academy_admin /
-- super_admin) — a center_admin can NOT expand their own scope (the write gate
-- is has_admin_or_higher(), which excludes center_admin).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- user_centers — additional center grants (primary center stays on users).
-- ----------------------------------------------------------------------------
create table public.user_centers (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  center_id uuid not null references public.centers(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_centers_unique unique (user_id, center_id)
);
create index idx_user_centers_user    on public.user_centers(user_id);
create index idx_user_centers_center  on public.user_centers(center_id);
create index idx_user_centers_academy on public.user_centers(academy_id);

create trigger trg_user_centers_updated before update on public.user_centers
  for each row execute function public.set_updated_at();

-- Useful too: the old single-center model never indexed users.center_id.
create index if not exists idx_users_center on public.users(center_id)
  where center_id is not null;

alter table public.user_centers enable row level security;

-- READ: a user always sees their OWN grants (so the app can load its scope);
-- admin tier sees the whole academy's grants. super_admin sees all.
create policy user_centers_read on public.user_centers
  for select using (
    public.is_super_admin()
    or user_id = auth.uid()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher())
  );

-- WRITE: admin tier only, within their academy, and the referenced user +
-- center must both belong to that academy (defence against cross-tenant
-- stitching via a forged academy_id).
create policy user_centers_admin_insert on public.user_centers
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
      and exists (select 1 from public.users u
                   where u.id = user_id and u.academy_id = academy_id)
      and exists (select 1 from public.centers c
                   where c.id = center_id and c.academy_id = academy_id)
    )
  );

create policy user_centers_admin_update on public.user_centers
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher())
  ) with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
      and exists (select 1 from public.users u
                   where u.id = user_id and u.academy_id = academy_id)
      and exists (select 1 from public.centers c
                   where c.id = center_id and c.academy_id = academy_id)
    )
  );

create policy user_centers_admin_delete on public.user_centers
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher())
  );

-- ----------------------------------------------------------------------------
-- current_user_in_center — the new membership vocabulary. NULL handling stays
-- with the callers (they keep their `center_id is null or ...` relaxation),
-- so this only answers the non-null "is this one of MY centers?" question.
-- ----------------------------------------------------------------------------
create or replace function public.current_user_in_center(p_center_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_center_id is not null
    and (
      p_center_id = (select center_id from public.users where id = auth.uid())
      or exists (
        select 1 from public.user_centers uc
        where uc.user_id = auth.uid()
          and uc.center_id = p_center_id
      )
    );
$$;

grant execute on function public.current_user_in_center(uuid) to authenticated;

-- ============================================================================
-- Restate the scope helpers, swapping `= current_user_center_id()` (and the
-- inline `= (select center_id from users …)`) for current_user_in_center(…).
-- Bodies are otherwise identical to their latest definitions — only the center
-- membership test changes. Single-center users see no behavioural difference.
-- ============================================================================

-- --- center_admin read helpers (20260509000400) -----------------------------
create or replace function public.center_admin_sees_center(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      p_center_id is null
      or public.current_user_in_center(p_center_id)
  end;
$$;

create or replace function public.center_admin_sees_student(p_student_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      exists (
        select 1 from public.students s
        where s.id = p_student_id
          and (s.center_id is null
               or public.current_user_in_center(s.center_id))
      )
  end;
$$;

create or replace function public.center_admin_sees_batch(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      exists (
        select 1 from public.batches b
        where b.id = p_batch_id
          and (b.center_id is null
               or public.current_user_in_center(b.center_id))
      )
  end;
$$;

-- --- batch_in_my_center (20260527000000) ------------------------------------
create or replace function public.batch_in_my_center(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.batches b
    where b.id = p_batch_id
      and (b.center_id is null
           or public.current_user_in_center(b.center_id))
  );
$$;

-- --- can_admin_center_scope (20260527000000) — feeds students/coaches/leads/
--     inventory/center_sports writes AND all of center-scoped finance. --------
create or replace function public.can_admin_center_scope(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    else false
  end;
$$;

-- --- can_manage_batches (20260527000000) — events (center, not sport-bound) --
create or replace function public.can_manage_batches(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    when 'head_coach'    then
      p_center_id is null or public.current_user_in_center(p_center_id)
    else false
  end;
$$;

-- --- student_in_my_center (20260606000000) — standalone media gate ----------
create or replace function public.student_in_my_center(p_student_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select coalesce((
    select s.center_id is null
        or public.current_user_in_center(s.center_id)
    from public.students s
    where s.id = p_student_id
  ), false);
$$;

-- --- can_provision_role (20260607000000) — who may create whom --------------
create or replace function public.can_provision_role(
  p_target_role public.user_role,
  p_center_id uuid
)
returns boolean language sql stable security definer set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) = 'super_admin'
      then true
    when public.role_rank((select role from public.users where id = auth.uid()))
         <= public.role_rank(p_target_role)
      then false
    when p_target_role in ('parent', 'student')
      then public.can_admin_center_scope(p_center_id)
    else case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then
        p_center_id is null or public.current_user_in_center(p_center_id)
      when 'head_coach'    then
        p_center_id is null or public.current_user_in_center(p_center_id)
      when 'coach'         then
        p_center_id is null or public.current_user_in_center(p_center_id)
      else false
    end
  end;
$$;

-- --- can_manage_batch_fields (latest 20260607000600) — batch writes ---------
create or replace function public.can_manage_batch_fields(
  p_center_id uuid,
  p_sport_id uuid
)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    when 'head_coach'    then
      (p_center_id is null or public.current_user_in_center(p_center_id))
      and (p_sport_id is null or public.head_coach_owns_sport(p_sport_id))
    else false
  end;
$$;

-- --- can_manage_student (latest 20260608000200) — student create/edit -------
create or replace function public.can_manage_student(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    when 'head_coach'    then
      p_center_id is null or public.current_user_in_center(p_center_id)
    else false
  end;
$$;

-- --- can_manage_coach_record (20260607000800) — coach create/edit -----------
create or replace function public.can_manage_coach_record(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    when 'head_coach'    then
      p_center_id is null or public.current_user_in_center(p_center_id)
    else false
  end;
$$;

-- --- head_coach_sees_coach (20260608000100) — coaches read narrowing --------
create or replace function public.head_coach_sees_coach(p_coach_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'head_coach' then exists (
      select 1
      from public.coaches c
      where c.id = p_coach_id
        and (c.center_id is null
             or public.current_user_in_center(c.center_id))
        and (
          not exists (
            select 1 from public.coach_sports cs where cs.coach_id = c.id
          )
          or exists (
            select 1 from public.coach_sports cs
            where cs.coach_id = c.id
              and public.head_coach_owns_sport(cs.sport_id)
          )
        )
    )
    else true
  end;
$$;

-- --- can_target_announcement (20260608000000) — center_admin/head_coach
--     compose targeting. Only the center-membership tests change; head_coach
--     stays sport-scoped. NOTE: send-announcement still resolves sport-target
--     recipients against current_user_center_id() (primary center only) — a
--     multi-center center_admin targeting a sport enabled only at a NON-primary
--     center will pass validation but reach no one there until that edge fn is
--     widened. Tracked in the change log.
create or replace function public.can_target_announcement(
  p_target_roles   public.user_role[],
  p_target_batches uuid[],
  p_target_centers uuid[],
  p_target_sports  uuid[]
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role public.user_role := (select role from public.users where id = auth.uid());
  b uuid;
  c uuid;
  s uuid;
  v_has_roles   boolean := coalesce(array_length(p_target_roles,   1), 0) > 0;
  v_has_batches boolean := coalesce(array_length(p_target_batches, 1), 0) > 0;
  v_has_centers boolean := coalesce(array_length(p_target_centers, 1), 0) > 0;
  v_has_sports  boolean := coalesce(array_length(p_target_sports,  1), 0) > 0;
begin
  if v_role in ('academy_owner', 'academy_admin') then
    return true;
  end if;

  if v_has_roles then
    return false;
  end if;
  if not (v_has_batches or v_has_centers or v_has_sports) then
    return false;
  end if;

  if v_role = 'center_admin' then
    foreach c in array coalesce(p_target_centers, '{}'::uuid[]) loop
      if not public.current_user_in_center(c) then
        return false;
      end if;
    end loop;
    foreach b in array coalesce(p_target_batches, '{}'::uuid[]) loop
      if not public.batch_in_my_center(b) then
        return false;
      end if;
    end loop;
    foreach s in array coalesce(p_target_sports, '{}'::uuid[]) loop
      if not exists (
        select 1 from public.center_sports cs
        where public.current_user_in_center(cs.center_id)
          and cs.sport_id = s
      ) then
        return false;
      end if;
    end loop;
    return true;

  elsif v_role = 'head_coach' then
    if v_has_centers then
      return false;
    end if;
    foreach b in array coalesce(p_target_batches, '{}'::uuid[]) loop
      if not (public.batch_in_my_center(b) and public.batch_in_my_sport(b)) then
        return false;
      end if;
    end loop;
    foreach s in array coalesce(p_target_sports, '{}'::uuid[]) loop
      if not public.head_coach_owns_sport(s) then
        return false;
      end if;
    end loop;
    return true;

  elsif v_role = 'coach' then
    if v_has_centers or v_has_sports then
      return false;
    end if;
    foreach b in array coalesce(p_target_batches, '{}'::uuid[]) loop
      if not public.coach_owns_batch(b) then
        return false;
      end if;
    end loop;
    return true;
  end if;

  return false;
end;
$$;


-- ############################################################################
-- ## SECTION 2/8 : 20260614000100_inventory_per_location_stock.sql
-- ############################################################################

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


-- ############################################################################
-- ## SECTION 3/8 : 20260614000200_support_ticket_number.sql
-- ############################################################################

-- ============================================================================
-- Human-readable support ticket number. [Issue #10]
--
-- Tickets only had a UUID id — useless for a non-technical academy user to quote
-- ("show me the ticket number"). Add a friendly sequential `ticket_number`
-- (global sequence; unique, increasing) shown on the ticket + the raise
-- confirmation. No new table/RLS — it's a column on the existing
-- support_tickets (its RLS is unchanged), so no pgTAP needed here.
-- ============================================================================

create sequence if not exists public.support_ticket_number_seq;

alter table public.support_tickets
  add column ticket_number bigint;

-- Backfill existing tickets in creation order so early tickets get low numbers.
with ordered as (
  select id, row_number() over (order by created_at, id) as rn
  from public.support_tickets
)
update public.support_tickets t
  set ticket_number = o.rn
  from ordered o
  where o.id = t.id;

-- Advance the sequence past the highest assigned number.
select setval(
  'public.support_ticket_number_seq',
  coalesce((select max(ticket_number) from public.support_tickets), 0) + 1,
  false
);

alter table public.support_tickets
  alter column ticket_number set default nextval('public.support_ticket_number_seq'),
  alter column ticket_number set not null;

create unique index uq_support_tickets_number
  on public.support_tickets(ticket_number);


-- ############################################################################
-- ## SECTION 4/8 : 20260614000300_support_center_admin_raise.sql
-- ############################################################################

-- ============================================================================
-- Support tickets: let center_admin RAISE + reply; owner/admin still RESOLVE.
-- [follow-up to issue #10]
--
-- center_admin already READS their academy's tickets (support_tickets_read) but
-- could not file one or reply — insert was owner/admin only. This opens raising
-- + replying to center_admin so they have an in-app support channel that the
-- academy owner/admin can see and mark resolved.
--
-- UPDATE is deliberately left as owner/admin (+ super_admin): the academy's
-- owner/admin triage and mark center_admin tickets resolved. center_admin gets
-- raise + reply + read only.
-- ============================================================================

drop policy support_tickets_owner_insert on public.support_tickets;
create policy support_tickets_insert on public.support_tickets
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin'
      )
    )
  );

drop policy support_msgs_insert on public.support_ticket_messages;
create policy support_msgs_insert on public.support_ticket_messages
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin'
      )
      and is_staff = false
    )
  );


-- ############################################################################
-- ## SECTION 5/8 : 20260614000400_academy_custom_sports.sql
-- ############################################################################

-- ============================================================================
-- Academy-scoped custom sports — let a center_admin (or admin tier) CREATE a new
-- sport name, not just pick from the global catalog.
--
-- `sports` was a single global catalog, super_admin-write only, read by everyone
-- (`using (true)`). We add a nullable `academy_id`:
--   * academy_id IS NULL  → global catalog sport (super_admin curated, seen by all)
--   * academy_id = X      → X's private custom sport (created in-app, seen only by X)
--
-- Reads are tightened so one academy's custom sports never leak into another's
-- pickers. The global `code` UNIQUE is relaxed to "unique within scope" so two
-- academies can both coin e.g. `frisbee` without colliding with each other or
-- the global catalog.
-- ============================================================================

alter table public.sports
  add column academy_id uuid references public.academies(id) on delete cascade;

-- Relax the global UNIQUE(code): global codes stay unique among themselves;
-- per-academy codes are unique within that academy.
alter table public.sports drop constraint sports_code_key;
create unique index uq_sports_code_global
  on public.sports(code) where academy_id is null;
create unique index uq_sports_code_academy
  on public.sports(academy_id, code) where academy_id is not null;
create index idx_sports_academy
  on public.sports(academy_id) where academy_id is not null;

-- Tighten read: global catalog + the caller's own academy (super_admin sees all).
drop policy sports_authenticated_read on public.sports;
create policy sports_read on public.sports
  for select to authenticated using (
    public.is_super_admin()
    or academy_id is null
    or academy_id = public.current_user_academy_id()
  );

-- super_admin keeps full write via the existing sports_super_admin_write (global
-- catalog). Add academy-scoped create/edit for owner/admin/center_admin — they
-- may only touch THEIR academy's custom sports, never the global catalog.
create policy sports_academy_insert on public.sports
  for insert to authenticated with check (
    academy_id is not null
    and academy_id = public.current_user_academy_id()
    and public.current_user_role() in (
      'academy_owner', 'academy_admin', 'center_admin'
    )
  );

create policy sports_academy_update on public.sports
  for update to authenticated using (
    academy_id is not null
    and academy_id = public.current_user_academy_id()
    and public.current_user_role() in (
      'academy_owner', 'academy_admin', 'center_admin'
    )
  ) with check (
    academy_id is not null
    and academy_id = public.current_user_academy_id()
    and public.current_user_role() in (
      'academy_owner', 'academy_admin', 'center_admin'
    )
  );

-- Deletes stay super_admin-only (sports_super_admin_write) — academies deactivate
-- a custom sport via is_active rather than hard-deleting (it may be referenced by
-- batches/students). center_sports is the per-center enable/disable toggle.


-- ############################################################################
-- ## SECTION 6/8 : 20260614000500_signup_default_owner.sql
-- ############################################################################

-- ============================================================================
-- Self-signup defaults to academy_owner (was 'student'). [Issue: signup role]
--
-- A plain self-signup is someone creating their OWN academy — they should land
-- as academy_owner, not student. Today the hardened trigger (20260607000100)
-- defaults untrusted signups to 'student'; that only "worked" because the signup
-- form immediately calls bootstrap_owner_academy() when email confirmation is
-- OFF. With email confirmation ON, the user verifies, signs in, and is stuck as
-- a student (no inline bootstrap) — the bug the client reported.
--
-- Fix: default the role to 'academy_owner'. Everything else about the security
-- hardening is unchanged — privileged fields (academy_id / center_id / a non-
-- default role / links) are STILL only honoured from a trusted source
-- (app_metadata, or user_metadata when invited_at is set). So:
--   • self-signup → academy_owner with academy_id = NULL. An owner with no
--     academy can't read/write ANY tenant (every RLS gate is academy_id =
--     current_user_academy_id(), which is NULL → matches nothing) — they can
--     only call bootstrap_owner_academy() on their own row. No escalation.
--   • RoleDashboard sees needsAcademySetup (owner + null academy) and shows the
--     SetupAcademyPage → bootstrap → home. The email-confirm path now completes.
--   • Invited users (parent/coach/etc.) are unaffected — their role comes from
--     the trusted invite path (invited_at set), not this default.
--   • The forged-academy_id escalation stays closed (academy_id is still NULL
--     for self-signups).
-- ============================================================================

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_app  jsonb := coalesce(new.raw_app_meta_data, '{}'::jsonb);
  -- The only trusted source of privileged fields: app_metadata (service-role
  -- only), or user_metadata for admin-driven invites (invited_at set).
  v_trusted jsonb := case
    when v_app ? 'role'             then v_app
    when new.invited_at is not null then v_user
    else '{}'::jsonb
  end;
  -- Untrusted self-signup → academy_owner (creating their own academy); a
  -- trusted source can still specify any role explicitly.
  v_role public.user_role :=
    coalesce((v_trusted->>'role')::public.user_role, 'academy_owner');
  v_academy_id uuid := nullif(v_trusted->>'academy_id', '')::uuid;
  v_center_id uuid := nullif(v_trusted->>'center_id', '')::uuid;
  v_link_student_id uuid := nullif(v_trusted->>'link_to_student_id', '')::uuid;
  v_link_relationship text := coalesce(v_trusted->>'link_relationship', 'parent');
  v_link_coach_id uuid := nullif(v_trusted->>'link_coach_id', '')::uuid;
  v_link_student_login_id uuid := nullif(v_trusted->>'link_student_login_id', '')::uuid;
  v_must_change boolean := (v_trusted ? 'role' and v_academy_id is not null);
begin
  insert into public.users (
    id, email, phone, role, first_name, last_name,
    academy_id, center_id, must_change_password
  ) values (
    new.id,
    new.email,
    new.phone,
    v_role,
    v_user->>'first_name',   -- non-privileged: fine to trust from the client
    v_user->>'last_name',
    v_academy_id,
    v_center_id,
    v_must_change
  )
  on conflict (id) do nothing;

  -- Parent linking — only when role is 'parent' and the invite carried a link.
  if v_role = 'parent' and v_link_student_id is not null
     and v_academy_id is not null then
    insert into public.parent_links
      (academy_id, parent_user_id, student_id, relationship, is_primary)
    values
      (v_academy_id, new.id, v_link_student_id, v_link_relationship, true)
    on conflict do nothing;
  end if;

  -- Coach login — connect the new user to an existing coaches row.
  if v_link_coach_id is not null then
    update public.coaches set user_id = new.id where id = v_link_coach_id;
  end if;

  -- Student login — connect the new user to an existing students row.
  if v_link_student_login_id is not null then
    update public.students set user_id = new.id where id = v_link_student_login_id;
  end if;

  return new;
end;
$$;


-- ############################################################################
-- ## SECTION 7/8 : 20260615000000_academy_payment_gateways.sql
-- ############################################################################

-- ============================================================================
-- Per-academy payment gateway credentials ("bring your own gateway").
--
-- An academy owner can configure their OWN Razorpay / Paytm merchant
-- credentials; payments in that academy then route through their account
-- (with a fallback to the platform-wide keys when nothing is configured —
-- see supabase/functions/_shared/payment_gateway.ts).
--
-- SECURITY MODEL (invariant #4 — secrets never reach a client):
--   • The API secret + webhook secret are stored in **Supabase Vault**
--     (encrypted at rest), NOT in this table. The table holds only the vault
--     reference (uuid) + the non-secret public identifier (Razorpay key_id /
--     Paytm MID) + flags.
--   • Secrets are **write-only** from any client's perspective. The owner sets
--     them via the SECURITY DEFINER RPC `set_payment_gateway`; no client read
--     path (table RLS, the status view, or the RPC) ever returns a secret.
--   • Only edge functions (service_role) can decrypt, via
--     `get_payment_gateway_credentials`, whose EXECUTE is revoked from
--     anon/authenticated and granted to service_role only.
--   • Clients read the `academy_payment_gateway_status` view, which exposes
--     "configured?" booleans — never the secret or even its vault id.
--
-- Only the academy **owner** manages these (owner-exclusive, like academy
-- settings). RLS is the real gate; the Flutter `Capabilities` mirror only hides
-- the entry point.
-- ============================================================================

create table public.academy_payment_gateways (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,

  -- Which gateway this row configures.
  provider text not null check (provider in ('razorpay', 'paytm')),

  -- Public, non-secret identifier (Razorpay key_id `rzp_live_…` / Paytm MID).
  -- Safe to return to clients — it's handed to the checkout SDK anyway.
  key_id text,

  -- Vault references for the secrets. NULL = not yet configured. These are
  -- harmless pointers (useless without vault decrypt rights) but are still
  -- excluded from the client-facing status view.
  secret_vault_id uuid,
  webhook_secret_vault_id uuid,

  -- Non-secret provider-specific config. Razorpay uses none. Paytm uses
  -- {"website": "...", "environment": "stage"|"prod"} (the website name and
  -- which Paytm gateway host to hit). Safe to expose to the owner client.
  config jsonb not null default '{}'::jsonb,

  -- Owner toggle: is this the gateway used to charge in this academy? At most
  -- one provider may be enabled per academy (enforced by `set_payment_gateway`).
  is_enabled boolean not null default false,

  -- When the API secret was last written (drives the "configured" UI hint).
  secret_set_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (academy_id, provider)
);

create trigger trg_academy_payment_gateways_updated
  before update on public.academy_payment_gateways
  for each row execute function public.set_updated_at();

alter table public.academy_payment_gateways enable row level security;

-- Read: the academy OWNER (their own academy) + super_admin. Note the read
-- still exposes `secret_vault_id`/`webhook_secret_vault_id` at the table level,
-- so clients must read the status VIEW below, not the table directly.
create policy academy_payment_gateways_owner_read
  on public.academy_payment_gateways
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_role('academy_owner')
    )
  );

-- Direct writes (DML) are reserved for super_admin (cleanup/troubleshooting).
-- Owners NEVER write this table directly — they go through the SECURITY DEFINER
-- `set_payment_gateway` / `clear_payment_gateway` RPCs, which validate ownership
-- and keep the secret out of the row. This is intentional: it centralises the
-- secret-handling path so no owner-facing policy can ever expose a secret.
create policy academy_payment_gateways_super_write
  on public.academy_payment_gateways
  for all using (public.is_super_admin())
  with check (public.is_super_admin());

-- ----------------------------------------------------------------------------
-- Client-facing status view — safe columns only (no secrets, no vault ids).
-- `security_invoker` so the base-table RLS above still applies per caller.
-- ----------------------------------------------------------------------------
create view public.academy_payment_gateway_status
  with (security_invoker = true)
as
  select
    academy_id,
    provider,
    key_id,
    is_enabled,
    config,
    (secret_vault_id is not null)         as secret_configured,
    (webhook_secret_vault_id is not null) as webhook_configured,
    secret_set_at,
    updated_at
  from public.academy_payment_gateways;

grant select on public.academy_payment_gateway_status to authenticated;

-- ============================================================================
-- RPC: set_payment_gateway — owner writes credentials (secret → Vault).
--   p_api_secret / p_webhook_secret: pass NULL to leave the existing secret
--   unchanged (so the owner can toggle `is_enabled` or update key_id without
--   re-typing secrets). Pass a non-empty string to set/replace.
-- ============================================================================
create or replace function public.set_payment_gateway(
  p_provider text,
  p_key_id text,
  p_api_secret text default null,
  p_webhook_secret text default null,
  p_enabled boolean default false,
  p_config jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_academy uuid := public.current_user_academy_id();
  v_role public.user_role := public.current_user_role();
  v_row public.academy_payment_gateways%rowtype;
  v_secret_id uuid;
  v_webhook_id uuid;
  v_name text;
  v_existing_id uuid;
  v_final_key_id text;
  v_final_config jsonb;
begin
  -- Owner-only, own academy only.
  if v_role is distinct from 'academy_owner' or v_academy is null then
    raise exception 'only the academy owner can manage payment gateways'
      using errcode = '42501';
  end if;
  if p_provider not in ('razorpay', 'paytm') then
    raise exception 'unsupported provider: %', p_provider using errcode = '22023';
  end if;

  select * into v_row
    from public.academy_payment_gateways
    where academy_id = v_academy and provider = p_provider;

  v_secret_id := v_row.secret_vault_id;
  v_webhook_id := v_row.webhook_secret_vault_id;

  -- API secret → Vault (create or update by stable name).
  if p_api_secret is not null and length(trim(p_api_secret)) > 0 then
    if v_secret_id is not null then
      perform vault.update_secret(v_secret_id, p_api_secret);
    else
      v_name := 'apg:' || v_academy::text || ':' || p_provider || ':api';
      select id into v_existing_id from vault.secrets where name = v_name;
      if v_existing_id is not null then
        perform vault.update_secret(v_existing_id, p_api_secret);
        v_secret_id := v_existing_id;
      else
        v_secret_id := vault.create_secret(
          p_api_secret, v_name, 'Payment API secret for academy ' || v_academy::text
        );
      end if;
    end if;
  end if;

  -- Webhook signing secret → Vault.
  if p_webhook_secret is not null and length(trim(p_webhook_secret)) > 0 then
    if v_webhook_id is not null then
      perform vault.update_secret(v_webhook_id, p_webhook_secret);
    else
      v_name := 'apg:' || v_academy::text || ':' || p_provider || ':webhook';
      select id into v_existing_id from vault.secrets where name = v_name;
      if v_existing_id is not null then
        perform vault.update_secret(v_existing_id, p_webhook_secret);
        v_webhook_id := v_existing_id;
      else
        v_webhook_id := vault.create_secret(
          p_webhook_secret, v_name, 'Payment webhook secret for academy ' || v_academy::text
        );
      end if;
    end if;
  end if;

  v_final_key_id := coalesce(nullif(trim(coalesce(p_key_id, '')), ''), v_row.key_id);
  -- Merge config: null = unchanged; otherwise shallow-merge over the existing.
  v_final_config := coalesce(v_row.config, '{}'::jsonb) || coalesce(p_config, '{}'::jsonb);

  -- Refuse to enable a half-configured gateway — that would break checkout.
  if p_enabled and (v_final_key_id is null or v_secret_id is null) then
    raise exception 'cannot enable %: key id and API secret are both required',
      p_provider using errcode = '22023';
  end if;
  -- Paytm additionally needs a website name + environment to route correctly.
  if p_enabled and p_provider = 'paytm' and (
       coalesce(v_final_config->>'website', '') = ''
       or coalesce(v_final_config->>'environment', '') not in ('stage', 'prod')
     ) then
    raise exception 'cannot enable paytm: website and environment (stage|prod) are required'
      using errcode = '22023';
  end if;

  insert into public.academy_payment_gateways as g (
    academy_id, provider, key_id, secret_vault_id, webhook_secret_vault_id,
    is_enabled, secret_set_at, config
  )
  values (
    v_academy, p_provider, v_final_key_id, v_secret_id, v_webhook_id,
    p_enabled,
    case when p_api_secret is not null and length(trim(p_api_secret)) > 0
         then now() else v_row.secret_set_at end,
    v_final_config
  )
  on conflict (academy_id, provider) do update set
    key_id = excluded.key_id,
    secret_vault_id = excluded.secret_vault_id,
    webhook_secret_vault_id = excluded.webhook_secret_vault_id,
    is_enabled = excluded.is_enabled,
    secret_set_at = excluded.secret_set_at,
    config = excluded.config,
    updated_at = now();

  -- At most one enabled gateway per academy.
  if p_enabled then
    update public.academy_payment_gateways
      set is_enabled = false, updated_at = now()
      where academy_id = v_academy and provider <> p_provider and is_enabled;
  end if;
end;
$$;

revoke execute on function
  public.set_payment_gateway(text, text, text, text, boolean, jsonb) from public, anon;
grant execute on function
  public.set_payment_gateway(text, text, text, text, boolean, jsonb) to authenticated;

-- ============================================================================
-- RPC: clear_payment_gateway — owner removes a gateway + its vault secrets.
-- ============================================================================
create or replace function public.clear_payment_gateway(p_provider text)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_academy uuid := public.current_user_academy_id();
  v_role public.user_role := public.current_user_role();
  v_row public.academy_payment_gateways%rowtype;
begin
  if v_role is distinct from 'academy_owner' or v_academy is null then
    raise exception 'only the academy owner can manage payment gateways'
      using errcode = '42501';
  end if;

  select * into v_row
    from public.academy_payment_gateways
    where academy_id = v_academy and provider = p_provider;
  if not found then
    return;
  end if;

  delete from public.academy_payment_gateways where id = v_row.id;

  if v_row.secret_vault_id is not null then
    delete from vault.secrets where id = v_row.secret_vault_id;
  end if;
  if v_row.webhook_secret_vault_id is not null then
    delete from vault.secrets where id = v_row.webhook_secret_vault_id;
  end if;
end;
$$;

revoke execute on function public.clear_payment_gateway(text) from public, anon;
grant execute on function public.clear_payment_gateway(text) to authenticated;

-- ============================================================================
-- RPC: get_payment_gateway_credentials — server-only credential read.
--   Returns DECRYPTED secrets, so EXECUTE is restricted to service_role; edge
--   functions call this with the service-role client. Never exposed to clients.
-- ============================================================================
create or replace function public.get_payment_gateway_credentials(
  p_academy_id uuid,
  p_provider text
)
returns table (
  key_id text,
  api_secret text,
  webhook_secret text,
  is_enabled boolean,
  config jsonb
)
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_row public.academy_payment_gateways%rowtype;
begin
  select * into v_row
    from public.academy_payment_gateways
    where academy_id = p_academy_id and provider = p_provider;
  if not found then
    return;
  end if;

  key_id := v_row.key_id;
  is_enabled := v_row.is_enabled;
  config := v_row.config;
  if v_row.secret_vault_id is not null then
    select decrypted_secret into api_secret
      from vault.decrypted_secrets where id = v_row.secret_vault_id;
  end if;
  if v_row.webhook_secret_vault_id is not null then
    select decrypted_secret into webhook_secret
      from vault.decrypted_secrets where id = v_row.webhook_secret_vault_id;
  end if;
  return next;
end;
$$;

revoke execute on function
  public.get_payment_gateway_credentials(uuid, text) from public, anon, authenticated;
grant execute on function
  public.get_payment_gateway_credentials(uuid, text) to service_role;


-- ############################################################################
-- ## SECTION 8/8 : 20260615000100_paytm_payments.sql
-- ############################################################################

-- ============================================================================
-- Paytm payment support — extends the payments / payment_attempts schema so the
-- same flow that records Razorpay receipts also records Paytm ones.
--
-- See 20260615000000_academy_payment_gateways.sql for per-academy credentials,
-- and supabase/functions/{create-payment-order,paytm-webhook} for the runtime.
--
-- Recording stays idempotent + verified (invariant #6): the paytm-webhook
-- confirms each txn against Paytm's Transaction Status API before inserting,
-- and dedupes on payments.unique_event_id (set to 'paytm:<orderId>').
-- ============================================================================

-- 'paytm' becomes a valid payment method (method is a CHECK, not an enum).
alter table public.payments
  drop constraint payments_method_check,
  add constraint payments_method_check
    check (method in ('razorpay', 'paytm', 'cash', 'cheque', 'bank_transfer', 'upi_manual'));

-- Paytm correlation IDs (NULL for non-Paytm payments), mirroring the
-- razorpay_* columns.
alter table public.payments
  add column if not exists paytm_order_id text,
  add column if not exists paytm_txn_id text;

-- payment_attempts now tracks which gateway each attempt used. razorpay_order_id
-- becomes nullable (Paytm attempts carry a paytm_order_id instead); the 3-retry
-- cap (attempt_number 1..3) and per-invoice counting are provider-agnostic.
alter table public.payment_attempts
  add column if not exists provider text not null default 'razorpay'
    check (provider in ('razorpay', 'paytm')),
  add column if not exists paytm_order_id text,
  alter column razorpay_order_id drop not null;

create unique index if not exists uniq_attempts_paytm_order
  on public.payment_attempts(paytm_order_id)
  where paytm_order_id is not null;


commit;
