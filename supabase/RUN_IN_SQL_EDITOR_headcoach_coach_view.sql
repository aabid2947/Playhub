-- ============================================================================
-- PlayHub — Fix: head_coach could view ALL coaches academy-wide.
-- Paste-and-run in the Supabase SQL editor. Idempotent (safe to re-run).
-- Mirrors migration 20260608000100_head_coach_coaches_read_scope.sql.
--
-- After this, a head_coach sees only coaches in their own center (or no center)
-- that are under one of THEIR sports; untagged (no coach_sports) coaches in
-- their center stay visible. All other roles are unchanged.
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

grant execute on function public.head_coach_sees_coach(uuid) to authenticated;

drop policy if exists coaches_academy_read on public.coaches;
create policy coaches_academy_read on public.coaches
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_center(center_id)
      and public.head_coach_sees_coach(id)
    )
  );
