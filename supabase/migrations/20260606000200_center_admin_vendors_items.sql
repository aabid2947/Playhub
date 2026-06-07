-- ============================================================================
-- Inventory write parity for center_admin.
--
-- inventory_items was already upgraded to can_admin_center_scope (center_admin
-- writes its own center), but vendors was left on the coarse has_admin_or_higher
-- gate — so center_admin hit "permission denied" creating/editing vendors.
-- This RE-ASSERTS the items policies idempotently (covers environments where the
-- earlier upgrade wasn't applied) and brings vendors under the same helper.
--
-- inventory_items has a center_id → gated on can_admin_center_scope(center_id):
--   owner/admin = any, center_admin = own center or null, everyone else denied.
-- vendors are ACADEMY-level (no center_id) → gated on
-- can_admin_center_scope(null) → owner/admin + center_admin (academy-wide),
-- everyone else denied.
--
-- drop ... if exists makes this safe whether or not the prior policy names are
-- present in a given environment.
-- ============================================================================

-- vendors --------------------------------------------------------------------
drop policy if exists vendors_admin_insert  on public.vendors;
drop policy if exists vendors_admin_update  on public.vendors;
drop policy if exists vendors_admin_delete  on public.vendors;
drop policy if exists vendors_write_insert  on public.vendors;
drop policy if exists vendors_write_update  on public.vendors;
drop policy if exists vendors_write_delete  on public.vendors;

create policy vendors_write_insert on public.vendors
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(null::uuid))
  );

create policy vendors_write_update on public.vendors
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(null::uuid))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(null::uuid))
  );

create policy vendors_write_delete on public.vendors
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(null::uuid))
  );

-- inventory_items (idempotent re-assert) -------------------------------------
drop policy if exists inv_items_admin_insert  on public.inventory_items;
drop policy if exists inv_items_admin_update  on public.inventory_items;
drop policy if exists inv_items_admin_delete  on public.inventory_items;
drop policy if exists inv_items_write_insert  on public.inventory_items;
drop policy if exists inv_items_write_update  on public.inventory_items;
drop policy if exists inv_items_write_delete  on public.inventory_items;

create policy inv_items_write_insert on public.inventory_items
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy inv_items_write_update on public.inventory_items
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy inv_items_write_delete on public.inventory_items
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );
