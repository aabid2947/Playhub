-- ============================================================================
-- Coach student access tightened to "their batches" (view + edit only).
--
-- Reverses, FOR COACHES ONLY, the 2026-06-07 decision (20260607000700) that let
-- coaches create/edit any student in their center. A coach should see only the
-- students enrolled in batches they staff — not the whole center.
--
--   coach   READ   → only students enrolled in a batch they staff
--                    (student_assigned_to_me)
--   coach   UPDATE → only those same students (edit their batch students)
--   coach   INSERT → no (onboarding reverts to center_admin / head_coach / admin)
--   trainer READ   → likewise narrowed to their batch students (was academy-wide;
--                    they only ever staff-scope attendance/performance anyway)
--
-- head_coach + center_admin keep center-wide student create/edit (students carry
-- a center_id but no sport/batch, so theirs can't be narrowed further).
-- ============================================================================

-- Who (coach/trainer) may SEE a given student. Short-circuits TRUE for every
-- other role so the existing read clauses are unchanged for them.
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

-- READ: fold the coach/trainer narrowing into the existing policy (academy +
-- center_admin center scope + parent/student own-student + coach/trainer batch).
drop policy students_academy_read on public.students;
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

-- can_manage_student no longer includes coach (coach can't create student
-- records, and the center-wide edit path is removed for them — their edit goes
-- through the assigned-student clause on students_update below).
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

-- INSERT unchanged shape (now coach-excluded via can_manage_student).
drop policy students_insert on public.students;
create policy students_insert on public.students
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_student(center_id))
  );

-- UPDATE: management tiers (can_manage_student) OR a coach editing a student
-- in one of their own batches (student_assigned_to_me).
drop policy students_update on public.students;
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
