-- ============================================================================
-- head_coach no longer SEES or MANAGES a peer head_coach's coach record.
--
-- Org-hierarchy rule: a head_coach manages the coaches/trainers under them, not
-- other head coaches. Previously the coaches READ (head_coach_sees_coach) and
-- the coach WRITE gates (can_manage_coach_record, center-scoped) let a
-- head_coach see AND edit ANY coach in their center — including another
-- head_coach's own `coaches` row. This narrows both so a head_coach can no
-- longer see or edit a DIFFERENT head_coach's record (or retag its sports).
--
--   • Their OWN coach record is unaffected (they keep editing their own row).
--   • owner / academy_admin / center_admin are NEVER restricted — they still
--     see and manage every coach, head coaches included.
--
-- Mechanism: coach_is_foreign_head_coach(coach_id) is true ONLY when the
-- current user is a head_coach AND the target coach is linked to a DIFFERENT
-- head_coach login. It is AND-ed (negated) into the read helper, the coach-row
-- update policy, and the coach_sports write gate. The actor-role check lives
-- inside the helper, so it self-limits to head_coach callers.
--
-- No client change: the coaches list is RLS-scoped, so peer head coaches drop
-- out of every head_coach read path automatically. RLS is the hard gate.
-- ============================================================================

-- True only for a head_coach actor looking at a DIFFERENT head_coach's record.
-- INNER JOIN on users means a coach with no login (user_id null) is never a
-- "foreign head coach"; u.id <> auth.uid() excludes the actor's own record.
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
grant execute on function public.coach_is_foreign_head_coach(uuid) to authenticated;

-- READ: same center + sport scope as before, MINUS peer head coaches.
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
             or public.current_user_in_center(c.center_id))
        and (
          -- no sport tagged yet → center scope; else must share a sport
          not exists (
            select 1 from public.coach_sports cs where cs.coach_id = c.id
          )
          or exists (
            select 1 from public.coach_sports cs
            where cs.coach_id = c.id
              and public.head_coach_owns_sport(cs.sport_id)
          )
        )
    ) and not public.coach_is_foreign_head_coach(p_coach_id)
    else true
  end;
$$;

-- WRITE (coach_sports): can_manage_coach is used ONLY by the coach_sports write
-- policies. Add the exclusion so a head_coach can't retag a peer's sports.
create or replace function public.can_manage_coach(p_coach_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.academy_writes_allowed()
     and public.can_manage_coach_record(
       (select center_id from public.coaches where id = p_coach_id)
     )
     and not public.coach_is_foreign_head_coach(p_coach_id);
$$;

-- WRITE (coaches row): re-create coaches_update with the peer exclusion on both
-- USING (which row you may target) and WITH CHECK (what you may change it to).
drop policy coaches_update on public.coaches;
create policy coaches_update on public.coaches
  for update
  using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach_record(center_id)
        and not public.coach_is_foreign_head_coach(id))
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach_record(center_id)
        and not public.coach_is_foreign_head_coach(id))
  );
