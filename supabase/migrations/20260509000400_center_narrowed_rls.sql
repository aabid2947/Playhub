-- ============================================================================
-- Sprint 5 — Center-narrowed RLS for `center_admin`.
--
-- Until now `center_admin` could read every row in their academy because the
-- read policies only checked `academy_id`. They can write to attendance and
-- performance via has_coach_or_higher() but cannot edit students/batches.
-- This migration narrows their READS to their own center: they see students,
-- batches, batch_enrollments, attendance, performance_*, and invoices for
-- rows whose effective center matches users.center_id (or has no center).
--
-- Other roles are unaffected: super_admin / owner / admin still see academy-
-- wide; coaches / parents / students keep their existing narrowing.
--
-- Helpers:
--   center_admin_sees_center(center_id) — direct center_id check
--   center_admin_sees_student(student_id) — resolves student.center_id
--   center_admin_sees_batch(batch_id)   — resolves batch.center_id
--
-- Each helper short-circuits to true for non-center_admin callers, so the
-- existing policy expressions keep working for every other role.
-- ============================================================================

create or replace function public.center_admin_sees_center(p_center_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      p_center_id is null
      or p_center_id = (select center_id from public.users where id = auth.uid())
  end;
$$;

create or replace function public.center_admin_sees_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      exists (
        select 1 from public.students s
        where s.id = p_student_id
          and (s.center_id is null
               or s.center_id = (select center_id from public.users where id = auth.uid()))
      )
  end;
$$;

create or replace function public.center_admin_sees_batch(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      exists (
        select 1 from public.batches b
        where b.id = p_batch_id
          and (b.center_id is null
               or b.center_id = (select center_id from public.users where id = auth.uid()))
      )
  end;
$$;

grant execute on function public.center_admin_sees_center(uuid)  to authenticated;
grant execute on function public.center_admin_sees_student(uuid) to authenticated;
grant execute on function public.center_admin_sees_batch(uuid)   to authenticated;

-- ============================================================================
-- students -------------------------------------------------------------------
-- ============================================================================
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
    )
  );

-- ============================================================================
-- batches --------------------------------------------------------------------
-- ============================================================================
drop policy batches_academy_read on public.batches;
create policy batches_academy_read on public.batches
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_center(center_id)
    )
  );

-- ============================================================================
-- batch_enrollments ----------------------------------------------------------
-- ============================================================================
drop policy enrollments_academy_read on public.batch_enrollments;
create policy enrollments_academy_read on public.batch_enrollments
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_batch(batch_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- ============================================================================
-- attendance_records ---------------------------------------------------------
-- ============================================================================
drop policy attendance_academy_read on public.attendance_records;
create policy attendance_academy_read on public.attendance_records
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_batch(batch_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- ============================================================================
-- performance_assessments ----------------------------------------------------
-- ============================================================================
drop policy perf_assess_academy_read on public.performance_assessments;
create policy perf_assess_academy_read on public.performance_assessments
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_student(student_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- ============================================================================
-- performance_skills ---------------------------------------------------------
-- ============================================================================
drop policy perf_skills_academy_read on public.performance_skills;
create policy perf_skills_academy_read on public.performance_skills
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_student(student_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- ============================================================================
-- performance_media ----------------------------------------------------------
-- ============================================================================
drop policy perf_media_academy_read on public.performance_media;
create policy perf_media_academy_read on public.performance_media
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_student(student_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- ============================================================================
-- invoices -------------------------------------------------------------------
-- ============================================================================
drop policy invoices_academy_read on public.invoices;
create policy invoices_academy_read on public.invoices
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_student(student_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- invoice_line_items rides off invoices' visibility via the existing
-- exists-clause; updating it to also gate on center_admin keeps the
-- behaviour consistent.
drop policy invoice_lines_academy_read on public.invoice_line_items;
create policy invoice_lines_academy_read on public.invoice_line_items
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and exists (
        select 1 from public.invoices i
        where i.id = invoice_line_items.invoice_id
          and public.center_admin_sees_student(i.student_id)
          and (
            public.current_user_role() not in ('parent', 'student')
            or public.parent_can_see_student(i.student_id)
          )
      )
    )
  );
