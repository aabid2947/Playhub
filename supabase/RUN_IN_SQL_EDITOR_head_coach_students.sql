-- ============================================================================
-- PlayHub — Scope a head_coach's student view to their sport's batches.
-- Paste-and-run in the Supabase SQL editor. Idempotent (safe to re-run).
-- Mirrors migration 20260608000500_head_coach_sport_scoped_students.sql.
--
-- After this, a head_coach sees a student only if the student is actively
-- enrolled in a batch that is in the head_coach's center AND one of their
-- sports (head_coach → sport → batch → student). All other roles unchanged.
--
-- NOTE: applying this SQL alone fixes the visibility. A small app-side cleanup
-- (dropping a now-redundant center filter for head_coach) ships in the next
-- APK build — without it, a head_coach still won't see other students, but a
-- student enrolled in their batch yet carrying a different center_id could be
-- hidden until the new build lands.
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
    else true
  end;
$$;

grant execute on function public.head_coach_sees_student(uuid) to authenticated;

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
      and public.head_coach_sees_student(id)
    )
  );
