-- ============================================================================
-- Role capabilities — hierarchical "scope + management ladder"
--
-- Replaces the coarse has_admin_or_higher() / has_coach_or_higher() write
-- gates with capability helpers that encode the full matrix:
--
--   academy_owner / academy_admin → academy-wide
--   center_admin                  → their own center only
--   head_coach                    → manage batches + attendance/perf in own center
--   coach                         → attendance + performance for OWN batches
--   trainer                       → attendance for OWN batches (NO performance)
--
-- Behaviour changes vs the previous policies:
--   • trainer GAINS attendance write (was excluded from has_coach_or_higher)
--   • coach/trainer are RESTRICTED to their own batches (was academy-wide)
--   • center_admin GAINS scoped writes on students/coaches/batches in its center
--
-- Every helper is SECURITY DEFINER with a pinned search_path so it can read
-- users/students/batches past RLS. super_admin and the academy_id tenant
-- filter are applied by the *policies* (is_super_admin() OR (academy match AND
-- capability)), keeping the RLS-gotcha pattern: no bare `for all using`.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Scope helpers
-- ----------------------------------------------------------------------------

-- Does this batch belong to the caller's center (or have no center)?
create or replace function public.batch_in_my_center(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.batches b
    where b.id = p_batch_id
      and (b.center_id is null
           or b.center_id = public.current_user_center_id())
  );
$$;

-- Is the caller the coach assigned to this batch?
create or replace function public.coach_owns_batch(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.batches b
    join public.coaches c on c.id = b.coach_id
    where b.id = p_batch_id
      and c.user_id = auth.uid()
  );
$$;

-- ----------------------------------------------------------------------------
-- Capability helpers (role + scope; tenant filter applied by the policy)
-- ----------------------------------------------------------------------------

-- Admin tier, with center_admin narrowed to its own center.
-- Used for students, coaches, and other center-scoped admin entities.
create or replace function public.can_admin_center_scope(p_center_id uuid)
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
    else false
  end;
$$;

-- Batches: admin tier + head_coach, all narrowed to center where applicable.
create or replace function public.can_manage_batches(p_center_id uuid)
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

-- Enrollments carry no center_id; resolve via the batch.
create or replace function public.can_manage_enrollment(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_batches(
    (select center_id from public.batches where id = p_batch_id)
  );
$$;

-- Attendance: admin tier + center_admin/head_coach (center) + coach/trainer
-- (own batches). Attendance rows always carry a non-null batch_id.
create or replace function public.can_mark_attendance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then public.batch_in_my_center(p_batch_id)
    when 'head_coach'    then public.batch_in_my_center(p_batch_id)
    when 'coach'         then public.coach_owns_batch(p_batch_id)
    when 'trainer'       then public.coach_owns_batch(p_batch_id)
    else false
  end;
$$;

-- Performance: same ladder as attendance MINUS trainer. batch_id may be null
-- on a free-standing assessment, in which case the role-tier check applies.
create or replace function public.can_record_performance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then p_batch_id is null or public.batch_in_my_center(p_batch_id)
    when 'head_coach'    then p_batch_id is null or public.batch_in_my_center(p_batch_id)
    when 'coach'         then p_batch_id is null or public.coach_owns_batch(p_batch_id)
    else false  -- trainer and end-user roles
  end;
$$;

-- Performance child rows (skills/media) inherit the parent assessment's gate.
create or replace function public.can_record_perf_for_assessment(p_assessment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_record_performance(
    (select batch_id from public.performance_assessments where id = p_assessment_id)
  );
$$;

grant execute on function public.batch_in_my_center(uuid)            to authenticated;
grant execute on function public.coach_owns_batch(uuid)              to authenticated;
grant execute on function public.can_admin_center_scope(uuid)        to authenticated;
grant execute on function public.can_manage_batches(uuid)            to authenticated;
grant execute on function public.can_manage_enrollment(uuid)         to authenticated;
grant execute on function public.can_mark_attendance(uuid)           to authenticated;
grant execute on function public.can_record_performance(uuid)        to authenticated;
grant execute on function public.can_record_perf_for_assessment(uuid) to authenticated;

-- ============================================================================
-- students — admin tier + center_admin (own center). Split per-action.
-- ============================================================================
drop policy students_admin_write on public.students;

create policy students_insert on public.students
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy students_update on public.students
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy students_delete on public.students
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

-- ============================================================================
-- coaches — admin tier + center_admin (own center).
-- ============================================================================
drop policy coaches_admin_write on public.coaches;

create policy coaches_insert on public.coaches
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy coaches_update on public.coaches
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy coaches_delete on public.coaches
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

-- ============================================================================
-- batches — admin tier + center_admin + head_coach (own center).
-- ============================================================================
drop policy batches_admin_write on public.batches;

create policy batches_insert on public.batches
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batches(center_id))
  );

create policy batches_update on public.batches
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batches(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batches(center_id))
  );

create policy batches_delete on public.batches
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batches(center_id))
  );

-- ============================================================================
-- batch_enrollments — gated by the parent batch's center.
-- ============================================================================
drop policy enrollments_admin_write on public.batch_enrollments;

create policy enrollments_insert on public.batch_enrollments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_enrollment(batch_id))
  );

create policy enrollments_update on public.batch_enrollments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_enrollment(batch_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_enrollment(batch_id))
  );

create policy enrollments_delete on public.batch_enrollments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_enrollment(batch_id))
  );

-- ============================================================================
-- attendance_records — replace coach insert/update with the ladder.
-- (admin delete policy unchanged.)
-- ============================================================================
drop policy attendance_coach_insert on public.attendance_records;
drop policy attendance_coach_update on public.attendance_records;

create policy attendance_write_insert on public.attendance_records
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_mark_attendance(batch_id))
  );

create policy attendance_write_update on public.attendance_records
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_mark_attendance(batch_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_mark_attendance(batch_id))
  );

-- ============================================================================
-- performance_assessments — coach insert/update become the ladder (no trainer).
-- ============================================================================
drop policy perf_assess_coach_insert on public.performance_assessments;
drop policy perf_assess_coach_update on public.performance_assessments;

create policy perf_assess_write_insert on public.performance_assessments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_performance(batch_id))
  );

create policy perf_assess_write_update on public.performance_assessments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_performance(batch_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_performance(batch_id))
  );

-- ============================================================================
-- performance_skills — inherit the parent assessment's gate.
-- ============================================================================
drop policy perf_skills_coach_insert on public.performance_skills;
drop policy perf_skills_coach_update on public.performance_skills;
drop policy perf_skills_coach_delete on public.performance_skills;

create policy perf_skills_write_insert on public.performance_skills
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_perf_for_assessment(assessment_id))
  );

create policy perf_skills_write_update on public.performance_skills
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_perf_for_assessment(assessment_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_perf_for_assessment(assessment_id))
  );

create policy perf_skills_write_delete on public.performance_skills
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_perf_for_assessment(assessment_id))
  );

-- ============================================================================
-- performance_media — inherit the parent assessment's gate.
-- ============================================================================
drop policy perf_media_coach_insert on public.performance_media;
drop policy perf_media_coach_update on public.performance_media;
drop policy perf_media_coach_delete on public.performance_media;

create policy perf_media_write_insert on public.performance_media
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_perf_for_assessment(assessment_id))
  );

create policy perf_media_write_update on public.performance_media
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_perf_for_assessment(assessment_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_perf_for_assessment(assessment_id))
  );

create policy perf_media_write_delete on public.performance_media
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_record_perf_for_assessment(assessment_id))
  );
