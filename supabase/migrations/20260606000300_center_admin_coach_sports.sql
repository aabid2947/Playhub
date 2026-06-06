-- ============================================================================
-- coach_sports write parity for center_admin.
--
-- center_admin can create/edit coaches in their center (coaches_insert rides
-- can_admin_center_scope), but coach_sports — the coach↔sport qualification
-- junction that setCoachSports() writes immediately after a coach is saved —
-- was left on has_admin_or_higher. So a center_admin's "new coach" save
-- inserted the coach, then failed assigning sports under RLS ("permission
-- denied"). This scopes coach_sports writes to the COACH's center, mirroring
-- the coaches policy.
--
-- can_manage_coach() is SECURITY DEFINER so the coaches lookup inside the
-- policy doesn't recurse through RLS (same pattern as can_manage_enrollment).
-- A coach with a null center_id is manageable by any center_admin in the
-- academy (can_admin_center_scope(null) = true) — matching how coaches are
-- created (new coaches default to no center).
-- ============================================================================

create or replace function public.can_manage_coach(p_coach_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_admin_center_scope(
    (select center_id from public.coaches where id = p_coach_id)
  );
$$;

grant execute on function public.can_manage_coach(uuid) to authenticated;

drop policy if exists coach_sports_admin_insert  on public.coach_sports;
drop policy if exists coach_sports_admin_update  on public.coach_sports;
drop policy if exists coach_sports_admin_delete  on public.coach_sports;
drop policy if exists coach_sports_write_insert  on public.coach_sports;
drop policy if exists coach_sports_write_update  on public.coach_sports;
drop policy if exists coach_sports_write_delete  on public.coach_sports;

create policy coach_sports_write_insert on public.coach_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach(coach_id))
  );

create policy coach_sports_write_update on public.coach_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach(coach_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach(coach_id))
  );

create policy coach_sports_write_delete on public.coach_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach(coach_id))
  );
