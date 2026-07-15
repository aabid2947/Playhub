-- ============================================================================
-- Follow-up to 20260714000000: a head_coach should see/manage NO head_coach
-- coach records in the Coaches section — INCLUDING their OWN — not just peers.
-- A head_coach manages the coaches/trainers under them; head_coach records
-- (their own included) are simply not part of that management surface.
--
-- Widen coach_is_foreign_head_coach to match ANY head_coach when the actor is a
-- head_coach (drop the "u.id <> auth.uid()" self carve-out). The read helper
-- (head_coach_sees_coach), the coaches_update policy, and can_manage_coach all
-- call this function BY NAME, so they pick up the change automatically: a
-- head_coach now can no longer SEE, EDIT, or RETAG any head_coach coach record,
-- their own included.
--
-- Sport authority is unaffected: head_coach_owns_sport is SECURITY DEFINER and
-- reads the coach_sports directly, so hiding the head_coach's own coaches row
-- from RLS does not shrink their sport scope.
--
-- NOTE: the function name keeps "foreign" for continuity with 20260714000000,
-- but it now also matches the actor's OWN record — see the comment below.
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
     );
$$;

comment on function public.coach_is_foreign_head_coach(uuid) is
  'True when the current user is a head_coach and the target coach is linked to '
  'ANY head_coach (the actor''s own record included). Negated into '
  'head_coach_sees_coach / coaches_update / can_manage_coach so a head_coach '
  'neither sees nor manages any head_coach coach record.';
