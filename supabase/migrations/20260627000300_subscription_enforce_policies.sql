-- ============================================================================
-- Subscription enforcement — Phase 1c: gate the WRITE policies that bypass the
-- (now-gated) capability helpers.
--
-- Two groups can't be covered by gating a helper:
--   1. Policies that call can_admin_center_scope() DIRECTLY — that helper is
--      reused in the finance READ gate, so it must stay un-gated; we add the
--      guard at the policy instead. (leads, inventory_items, fee_structures,
--      discount_structures, center_sports, students_update coach branch.)
--   2. Policies with inline has_admin_or_higher() / role-list checks.
--      (academy_sports, vendors, inventory_categories, inventory_movements,
--      parent_links, announcements, event_registrations, event_results.)
--
-- Mechanism: add `and public.academy_writes_allowed()` to the tenant branch.
-- super_admin keeps writing via the policy's separate is_super_admin() branch.
-- Reads are untouched. Policy bodies are reproduced verbatim from their latest
-- definitions with only the guard added. See SUBSCRIPTION_ENFORCEMENT.md.
--
-- NOT gated (deliberate carve-outs): saas_* (the pay-to-unlock path), support
-- tickets, messaging + notifications, and the parent/student event self-register
-- branch (a frozen academy must not block its customers' self-service).
-- inventory_stock has no client write policy (trigger-maintained) — nothing to do.
-- ============================================================================

-- ---- students_update: gate the inline coach branch too ---------------------
drop policy students_update on public.students;
create policy students_update on public.students
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and (public.can_manage_student(center_id)
             or (public.current_user_role() = 'coach'
                 and public.student_assigned_to_me(id))))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and (public.can_manage_student(center_id)
             or (public.current_user_role() = 'coach'
                 and public.student_assigned_to_me(id))))
  );

-- ---- leads (direct can_admin_center_scope) ---------------------------------
drop policy leads_write_insert on public.leads;
drop policy leads_write_update on public.leads;
drop policy leads_write_delete on public.leads;

create policy leads_write_insert on public.leads
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(preferred_center_id))
  );
create policy leads_write_update on public.leads
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(preferred_center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(preferred_center_id))
  );
create policy leads_write_delete on public.leads
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(preferred_center_id))
  );

-- ---- inventory_items (direct can_admin_center_scope) -----------------------
drop policy inv_items_write_insert on public.inventory_items;
drop policy inv_items_write_update on public.inventory_items;
drop policy inv_items_write_delete on public.inventory_items;

create policy inv_items_write_insert on public.inventory_items
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy inv_items_write_update on public.inventory_items
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy inv_items_write_delete on public.inventory_items
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );

-- ---- fee_structures (templates; direct can_admin_center_scope) -------------
drop policy fee_structures_write_insert on public.fee_structures;
drop policy fee_structures_write_update on public.fee_structures;
drop policy fee_structures_write_delete on public.fee_structures;

create policy fee_structures_write_insert on public.fee_structures
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy fee_structures_write_update on public.fee_structures
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy fee_structures_write_delete on public.fee_structures
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );

-- ---- discount_structures (templates; direct can_admin_center_scope) --------
drop policy ds_write_insert on public.discount_structures;
drop policy ds_write_update on public.discount_structures;
drop policy ds_write_delete on public.discount_structures;

create policy ds_write_insert on public.discount_structures
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy ds_write_update on public.discount_structures
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy ds_write_delete on public.discount_structures
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );

-- ---- center_sports (direct can_admin_center_scope) -------------------------
drop policy center_sports_write_insert on public.center_sports;
drop policy center_sports_write_update on public.center_sports;
drop policy center_sports_write_delete on public.center_sports;

create policy center_sports_write_insert on public.center_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy center_sports_write_update on public.center_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy center_sports_write_delete on public.center_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );

-- ---- academy_sports (catalog; inline has_admin_or_higher) ------------------
drop policy academy_sports_admin_insert on public.academy_sports;
drop policy academy_sports_admin_update on public.academy_sports;
drop policy academy_sports_admin_delete on public.academy_sports;

create policy academy_sports_admin_insert on public.academy_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy academy_sports_admin_update on public.academy_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy academy_sports_admin_delete on public.academy_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- vendors (inline has_admin_or_higher) ----------------------------------
drop policy vendors_admin_insert on public.vendors;
drop policy vendors_admin_update on public.vendors;
drop policy vendors_admin_delete on public.vendors;

create policy vendors_admin_insert on public.vendors
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy vendors_admin_update on public.vendors
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy vendors_admin_delete on public.vendors
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- inventory_categories (inline has_admin_or_higher) ---------------------
drop policy inv_cats_admin_insert on public.inventory_categories;
drop policy inv_cats_admin_update on public.inventory_categories;
drop policy inv_cats_admin_delete on public.inventory_categories;

create policy inv_cats_admin_insert on public.inventory_categories
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy inv_cats_admin_update on public.inventory_categories
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy inv_cats_admin_delete on public.inventory_categories
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- inventory_movements (inline staff role list) --------------------------
drop policy inv_moves_staff_insert on public.inventory_movements;
create policy inv_moves_staff_insert on public.inventory_movements
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin', 'head_coach', 'coach', 'trainer'
      )
    )
  );

-- ---- parent_links (inline has_admin_or_higher) -----------------------------
drop policy parent_links_admin_insert on public.parent_links;
drop policy parent_links_admin_update on public.parent_links;
drop policy parent_links_admin_delete on public.parent_links;

create policy parent_links_admin_insert on public.parent_links
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy parent_links_admin_update on public.parent_links
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy parent_links_admin_delete on public.parent_links
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- announcements (compose; can_target_announcement is plpgsql) -----------
drop policy announcements_compose_insert on public.announcements;
drop policy announcements_compose_update on public.announcements;
drop policy announcements_compose_delete on public.announcements;

create policy announcements_compose_insert on public.announcements
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.can_target_announcement(
        target_roles, target_batches, target_centers, target_sports
      )
    )
  );
create policy announcements_compose_update on public.announcements
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and (public.has_admin_or_higher() or created_by = auth.uid())
    )
  )
  with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and (public.has_admin_or_higher() or created_by = auth.uid())
      and public.can_target_announcement(
        target_roles, target_batches, target_centers, target_sports
      )
    )
  );
create policy announcements_compose_delete on public.announcements
  for delete using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and (public.has_admin_or_higher() or created_by = auth.uid())
    )
  );

-- ---- event_registrations: gate STAFF writes; keep parent/student self-register
drop policy event_regs_admin_insert on public.event_registrations;
drop policy event_regs_admin_update on public.event_registrations;
drop policy event_regs_admin_delete on public.event_registrations;

create policy event_regs_admin_insert on public.event_registrations
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (
          (public.has_admin_or_higher()
           or public.current_user_role() in ('center_admin', 'head_coach', 'coach'))
          and public.academy_writes_allowed()
        )
        or (
          public.current_user_role() in ('parent', 'student')
          and public.parent_can_see_student(student_id)
          and exists (
            select 1 from public.events e
            where e.id = event_id
              and e.academy_id = academy_id
              and e.status = 'published'
              and (e.registration_opens_at is null or e.registration_opens_at <= now())
              and (e.registration_closes_at is null or e.registration_closes_at >= now())
          )
        )
      )
    )
  );
create policy event_regs_admin_update on public.event_registrations
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.current_user_role() not in ('parent', 'student')
    )
  )
  with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.current_user_role() not in ('parent', 'student')
    )
  );
create policy event_regs_admin_delete on public.event_registrations
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- event_results (inline staff role list) --------------------------------
drop policy event_results_staff_insert on public.event_results;
create policy event_results_staff_insert on public.event_results
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin', 'head_coach', 'coach'
      )
    )
  );
