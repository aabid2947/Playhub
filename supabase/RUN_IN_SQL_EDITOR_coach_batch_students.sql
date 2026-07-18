-- ============================================================================
-- PlayHub — Restrict a coach's student access to their own batches.
-- Paste-and-run in the Supabase SQL editor. Idempotent (safe to re-run).
-- Mirrors migration 20260608000200_coach_batch_scoped_students.sql.
--
-- After this:
--   coach   → reads + edits ONLY students enrolled in batches they staff;
--             cannot create students (onboarding reverts to admin tiers).
--   trainer → reads narrowed the same way.
--   head_coach / center_admin / admin → unchanged (center-wide / academy-wide).
-- ============================================================================

create or replace function public.coach_sees_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'coach'   then public.student_assigned_to_me(p_student_id)
    when 'trainer' then public.student_assigned_to_me(p_student_id)
    else true
  end;
$$;

grant execute on function public.coach_sees_student(uuid) to authenticated;

drop policy if exists students_academy_read on public.students;
create policy students_academy_read on public.students
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_center(center_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(id)
      )
      and public.coach_sees_student(id)
    )
  );

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
    else false
  end;
$$;

drop policy if exists students_insert on public.students;
create policy students_insert on public.students
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_student(center_id))
  );

drop policy if exists students_update on public.students;
create policy students_update on public.students
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and (public.can_manage_student(center_id)
             or (public.current_user_role() = 'coach'
                 and public.student_assigned_to_me(id))))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and (public.can_manage_student(center_id)
             or (public.current_user_role() = 'coach'
                 and public.student_assigned_to_me(id))))
  );
