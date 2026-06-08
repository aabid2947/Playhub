-- ============================================================================
-- Bug: a head_coach could VIEW every coach in the academy.
--
-- coaches_academy_read (20260607000500) narrows only for center_admin
-- (center_admin_sees_center short-circuits TRUE for every other role), so a
-- head_coach saw all coaches academy-wide — including coaches for sports/centers
-- they have nothing to do with.
--
-- Fix: a head_coach sees only coaches in their own center (or no center) that
-- are under one of THEIR sports — mirroring the head_coach sport scope used for
-- batches. A coach with no coach_sports yet falls back to center scope (same
-- NULL-sport relaxation as batches, 20260607000600) so a just-created, not-yet-
-- tagged coach isn't immediately invisible to the head_coach who made it.
--
-- NOTE (intentional read⊂write asymmetry): can_manage_coach_record is
-- center-scoped (not sport-bound), so a head_coach can still EDIT a same-center
-- coach in another sport — but they can no longer SEE one, which is what was
-- asked. They reach editable coaches through this now-scoped list, so the
-- over-offer is only theoretical (a coach reached by some other path).
-- ============================================================================

create or replace function public.head_coach_sees_coach(p_coach_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'head_coach' then exists (
      select 1
      from public.coaches c
      where c.id = p_coach_id
        and (c.center_id is null
             or c.center_id = public.current_user_center_id())
        and (
          -- no sport tagged yet → fall back to center scope
          not exists (
            select 1 from public.coach_sports cs where cs.coach_id = c.id
          )
          -- or the coach is under one of the head_coach's sports
          or exists (
            select 1 from public.coach_sports cs
            where cs.coach_id = c.id
              and public.head_coach_owns_sport(cs.sport_id)
          )
        )
    )
    else true  -- every other role is governed by the existing clauses
  end;
$$;

grant execute on function public.head_coach_sees_coach(uuid) to authenticated;

-- Re-create the read policy with the head_coach narrowing folded in. The two
-- scope helpers each short-circuit TRUE for roles they don't govern, so:
--   super_admin / owner / academy_admin → both TRUE (full academy)
--   center_admin                        → narrowed by center, head_coach=TRUE
--   head_coach                          → center helper TRUE, narrowed by sport
--   coach / trainer / parent / student  → both TRUE (read scope unchanged)
drop policy coaches_academy_read on public.coaches;
create policy coaches_academy_read on public.coaches
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_center(center_id)
      and public.head_coach_sees_coach(id)
    )
  );
