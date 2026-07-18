-- ============================================================================
-- head_coach can create + edit COACH records (and their coach_sports) in their
-- own center — completing the "create coach -> assign to a batch" loop.
--
-- The coaches row is what batches.coach_id points at, so inviting a coach LOGIN
-- wasn't enough; the head_coach also needs to create the coaches record. As
-- with students, coach records carry a center_id but no sport, so this is
-- CENTER-scoped for the head_coach's center (same reach as center_admin for
-- coaches). DELETE stays admin / center_admin.
--
-- can_manage_coach() (used by the coach_sports junction policies) is redefined
-- to ride the same gate, so the coach form's setCoachSports() write also
-- succeeds for a head_coach.
-- ============================================================================

create or replace function public.can_manage_coach_record(p_center_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or p_center_id = public.current_user_center_id()
    when 'head_coach'    then
      p_center_id is null or p_center_id = public.current_user_center_id()
    else false
  end;
$$;

grant execute on function public.can_manage_coach_record(uuid) to authenticated;

-- coaches insert + update → include head_coach (own center). delete unchanged.
drop policy coaches_insert on public.coaches;
drop policy coaches_update on public.coaches;

create policy coaches_insert on public.coaches
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach_record(center_id))
  );

create policy coaches_update on public.coaches
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach_record(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach_record(center_id))
  );

-- coach_sports writes ride can_manage_coach(); widen it to head_coach too so a
-- head_coach's "new coach" save (which sets the coach's sports) succeeds.
create or replace function public.can_manage_coach(p_coach_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_coach_record(
    (select center_id from public.coaches where id = p_coach_id)
  );
$$;
