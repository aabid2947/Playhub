-- ============================================================================
-- Phase 5 — finish center_admin READ isolation on the secondary lists, and
-- align announcement reads to actual delivery.
--
-- center_narrowed_rls (20260509000400) already narrowed center_admin reads on
-- students / batches / enrollments / attendance / performance_* / invoices, and
-- Phase 4 narrowed payments + fee/discount assignments. This closes the
-- remaining academy-wide reads a center_admin shouldn't have:
--   coaches, leads, inventory_items, events, batch_staff → their own center.
--
-- Each rides the existing center_admin_sees_center / center_admin_sees_batch
-- helpers, which SHORT-CIRCUIT to true for every non-center_admin role — so
-- admins stay academy-wide and coaches/parents/students are unaffected.
--
-- Announcements: the per-user feed is the announcement_recipients rows; the
-- base table was readable academy-wide. Narrow it so non-admins see only
-- announcements delivered to them (or that they created), matching the feed.
-- (Admins keep the full compose/history view.)
--
-- NOT in scope (flagged): NULL-center semantics still mean "visible to every
-- center_admin" (a soft widening), and materialized KPI/analytics views bypass
-- RLS so dashboards may show academy-wide aggregates to a center_admin. Both
-- need a dedicated, signed-off change.
-- ============================================================================

-- coaches → center_admin sees their own center's coaches.
drop policy coaches_academy_read on public.coaches;
create policy coaches_academy_read on public.coaches
  for select using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.center_admin_sees_center(center_id))
  );

-- leads → center_admin sees their own center's leads (by preferred_center_id);
-- parents/students still excluded.
drop policy leads_academy_read on public.leads;
create policy leads_academy_read on public.leads
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
      and public.center_admin_sees_center(preferred_center_id)
    )
  );

-- inventory_items → center_admin sees their own center's items.
drop policy inv_items_academy_read on public.inventory_items;
create policy inv_items_academy_read on public.inventory_items
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
      and public.center_admin_sees_center(center_id)
    )
  );

-- events → center_admin sees their own center's events; the published-event
-- visibility for parents/students is preserved (they're not center_admins, so
-- center_admin_sees_center short-circuits true for them).
drop policy events_academy_read on public.events;
create policy events_academy_read on public.events
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_center(center_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or status in ('published', 'registration_closed', 'in_progress', 'completed')
      )
    )
  );

-- batch_staff → center_admin sees assignments for their own center's batches.
drop policy batch_staff_academy_read on public.batch_staff;
create policy batch_staff_academy_read on public.batch_staff
  for select using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.center_admin_sees_batch(batch_id))
  );

-- announcements → non-admins see only announcements delivered to them (a
-- recipient row) or that they created; admins keep the full academy view.
drop policy announcements_academy_read on public.announcements;
create policy announcements_read on public.announcements
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.has_admin_or_higher()
        or created_by = auth.uid()
        or exists (
          select 1 from public.announcement_recipients r
          where r.announcement_id = announcements.id
            and r.user_id = auth.uid()
        )
      )
    )
  );
