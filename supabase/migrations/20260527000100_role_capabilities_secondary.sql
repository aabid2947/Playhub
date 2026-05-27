-- ============================================================================
-- Role capabilities (part 2) — center-scope leads / events / inventory items
--
-- Extends the ladder to the secondary management surfaces:
--   • leads (+ activity log)  → admin tier + center_admin (their preferred center)
--   • events                  → admin tier + center_admin/head_coach (their center)
--   • inventory_items         → admin tier + center_admin (their center)
--
-- Left intentionally unchanged (academy-level master data or already-broad):
--   vendors, inventory_categories, inventory_movements (issue/return ledger,
--   open to all staff), event_registrations / event_results.
-- ============================================================================

-- Resolve a lead's preferred center so lead_activities can inherit its gate.
create or replace function public.can_admin_lead(p_lead_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_admin_center_scope(
    (select preferred_center_id from public.leads where id = p_lead_id)
  );
$$;

grant execute on function public.can_admin_lead(uuid) to authenticated;

-- ============================================================================
-- leads — admin tier + center_admin (preferred center).
-- ============================================================================
drop policy leads_admin_insert on public.leads;
drop policy leads_admin_update on public.leads;
drop policy leads_admin_delete on public.leads;

create policy leads_write_insert on public.leads
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(preferred_center_id))
  );

create policy leads_write_update on public.leads
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(preferred_center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(preferred_center_id))
  );

create policy leads_write_delete on public.leads
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(preferred_center_id))
  );

-- lead_activities — append-only; inherit the parent lead's center gate.
drop policy lead_activities_admin_insert on public.lead_activities;

create policy lead_activities_write_insert on public.lead_activities
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_lead(lead_id))
  );

-- ============================================================================
-- events — narrow the existing owner/admin/center_admin/head_coach writers
-- from academy-wide to center scope (can_manage_batches encodes exactly that
-- writer set). Delete stays admin-or-higher.
-- ============================================================================
drop policy events_admin_insert on public.events;
drop policy events_admin_update on public.events;

create policy events_write_insert on public.events
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batches(center_id))
  );

create policy events_write_update on public.events
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batches(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batches(center_id))
  );

-- ============================================================================
-- inventory_items — admin tier + center_admin (their center).
-- ============================================================================
drop policy inv_items_admin_insert on public.inventory_items;
drop policy inv_items_admin_update on public.inventory_items;
drop policy inv_items_admin_delete on public.inventory_items;

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
