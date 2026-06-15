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
