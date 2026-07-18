-- ============================================================================
-- head_coach AND coach can create + edit STUDENT records in their own center.
--
-- Originally students were a center_admin / admin record-management task; the
-- coaching roles were batch/sport scoped. This grants both head_coach and coach
-- center-scoped student create/edit so the people running training can onboard
-- athletes directly.
--
-- NOTE on scope: students carry a center_id but NO sport/batch, so this is
-- necessarily CENTER-wide for the user's own center (same reach as center_admin
-- for students) — it can't be narrowed to "their sport" or "their batch".
-- DELETE stays admin / center_admin (can_admin_center_scope) — coaching roles
-- onboard, they don't purge.
-- ============================================================================

create or replace function public.can_manage_student(p_center_id uuid)
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
    when 'coach'         then
      p_center_id is null or p_center_id = public.current_user_center_id()
    else false
  end;
$$;

grant execute on function public.can_manage_student(uuid) to authenticated;

-- students insert + update → can_manage_student (adds head_coach, own center).
-- delete is left on can_admin_center_scope (admin tier + center_admin only).
drop policy students_insert on public.students;
drop policy students_update on public.students;

create policy students_insert on public.students
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_student(center_id))
  );

create policy students_update on public.students
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_student(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_student(center_id))
  );
