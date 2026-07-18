-- ============================================================================
-- REVERT 20260714000100. Hiding a head_coach's OWN coach record at the RLS
-- level was wrong: the app reads `coaches where user_id = auth.uid()`
-- (myCoachRecordProvider) to derive a head_coach's sports (mySportIdsProvider)
-- and their manageable batches. With their own row RLS-hidden, that read
-- returned nothing, so a head_coach got ZERO sports in the batch / student /
-- coach sport pickers and an empty coach-shell batch list.
--
-- Restore coach_is_foreign_head_coach to PEER-ONLY (add back the "u.id <>
-- auth.uid()" self carve-out): a head_coach may READ + manage their OWN coach
-- record (needed functionally) but still not any OTHER head_coach's. Hiding the
-- own record from the *Coaches list* is a UI concern (handled client-side in
-- coaches_tab), NOT an RLS one — RLS gates data access, not list presentation.
--
-- The read helper (head_coach_sees_coach), coaches_update, and can_manage_coach
-- call this by name, so they all pick up the reverted body automatically.
-- ============================================================================

create or replace function public.coach_is_foreign_head_coach(p_coach_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_role() = 'head_coach'
     and exists (
       select 1
       from public.coaches c
       join public.users u on u.id = c.user_id
       where c.id = p_coach_id
         and u.role = 'head_coach'
         and u.id <> auth.uid()
     );
$$;

comment on function public.coach_is_foreign_head_coach(uuid) is
  'True when the current user is a head_coach and the target coach is linked to '
  'a DIFFERENT head_coach (peer). The actor''s OWN record is NOT foreign — they '
  'must read/manage it (myCoachRecordProvider derives their sports + batches '
  'from it). Negated into head_coach_sees_coach / coaches_update / '
  'can_manage_coach. The own record is hidden from the Coaches LIST client-side.';
