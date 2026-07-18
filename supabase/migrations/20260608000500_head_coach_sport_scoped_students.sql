-- ============================================================================
-- Scope a head_coach's STUDENT view to their sports — via the batch path:
--   head_coach → their sport(s) → batches in those sports → enrolled students.
--
-- Until now a head_coach's students read was academy-wide at RLS (only the app
-- list was center-filtered). This narrows the read so a head_coach sees a
-- student only if the student is ACTIVELY ENROLLED in a batch that is in the
-- head_coach's center AND one of their sports — the same batch_in_my_center +
-- batch_in_my_sport gates that already define their batch/attendance scope.
--
-- NOTES:
--  • Read only. can_manage_student (WRITE) stays center-scoped for head_coach
--    (documented 20260607000700) — so a head_coach can still EDIT a same-center
--    student, but now only SEES their sport's batch students. Reached through
--    the now-scoped list, so the over-offer is only theoretical (same pattern
--    as the head_coach coaches read, 20260608000100).
--  • A student not yet enrolled in any of the head_coach's batches is not
--    visible to them (by design — "sports → batch → students").
-- ============================================================================

create or replace function public.head_coach_sees_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'head_coach' then exists (
      select 1
      from public.batch_enrollments e
      where e.student_id = p_student_id
        and e.enrollment_status = 'active'
        and public.batch_in_my_center(e.batch_id)
        and public.batch_in_my_sport(e.batch_id)
    )
    else true  -- every other role governed by the existing read clauses
  end;
$$;

grant execute on function public.head_coach_sees_student(uuid) to authenticated;

-- Fold the head_coach narrowing into the students read policy. Each scope
-- helper short-circuits TRUE for roles it doesn't govern, so:
--   super_admin / owner / academy_admin → full academy
--   center_admin                        → own center (center_admin_sees_center)
--   head_coach                          → own-sport batch students (this fn)
--   coach / trainer                     → own-batch students (coach_sees_student)
--   parent / student                    → their own student (parent_can_see_student)
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
      and public.head_coach_sees_student(id)
    )
  );
