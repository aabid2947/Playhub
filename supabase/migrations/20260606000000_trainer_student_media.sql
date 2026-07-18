-- ============================================================================
-- Let TRAINERS (and coaches) share photos/videos of a student WITHOUT giving
-- them the formal performance-assessment form. Trainers stay "attendance +
-- media only"; they still cannot score skills (can_record_performance is
-- unchanged and still excludes trainer).
--
-- Mechanism: performance_media.assessment_id becomes nullable. A row with a
-- null assessment_id is "standalone student media" — evidence attached to a
-- student, not to a scored assessment. It still carries student_id + academy_id
-- so the existing parent/student read-scoping and the student gallery pick it
-- up automatically.
--
-- New capability `can_upload_student_media(student_id)` gates standalone media:
--   academy_owner / academy_admin → any student in academy
--   center_admin / head_coach     → students in their own center
--   coach / trainer               → students enrolled in a batch they run
-- ============================================================================

-- Standalone media has no parent assessment.
alter table public.performance_media
  alter column assessment_id drop not null;

-- ----------------------------------------------------------------------------
-- Scope helpers
-- ----------------------------------------------------------------------------

-- Is this student enrolled in a batch the caller (coach/trainer) runs?
create or replace function public.student_in_my_batch(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.batch_enrollments be
    join public.batches b on b.id = be.batch_id
    join public.coaches c on c.id = b.coach_id
    where be.student_id = p_student_id
      and c.user_id = auth.uid()
  );
$$;

-- Is this student in the caller's center (or center-less)?
create or replace function public.student_in_my_center(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select s.center_id is null
        or s.center_id = public.current_user_center_id()
    from public.students s
    where s.id = p_student_id
  ), false);
$$;

-- Can the caller attach standalone media to this student?
create or replace function public.can_upload_student_media(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then public.student_in_my_center(p_student_id)
    when 'head_coach'    then public.student_in_my_center(p_student_id)
    when 'coach'         then public.student_in_my_batch(p_student_id)
    when 'trainer'       then public.student_in_my_batch(p_student_id)
    else false
  end;
$$;

grant execute on function public.student_in_my_batch(uuid)        to authenticated;
grant execute on function public.student_in_my_center(uuid)       to authenticated;
grant execute on function public.can_upload_student_media(uuid)   to authenticated;

-- ----------------------------------------------------------------------------
-- performance_media TABLE policies — assessment-bound media keeps the
-- performance gate; standalone (assessment_id is null) media uses the new
-- upload capability (so trainers qualify for their own students).
-- ----------------------------------------------------------------------------
drop policy perf_media_write_insert on public.performance_media;
drop policy perf_media_write_update on public.performance_media;
drop policy perf_media_write_delete on public.performance_media;

create policy perf_media_write_insert on public.performance_media
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (assessment_id is not null
           and public.can_record_perf_for_assessment(assessment_id))
        or (assessment_id is null
           and public.can_upload_student_media(student_id))
      )
    )
  );

create policy perf_media_write_update on public.performance_media
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (assessment_id is not null
           and public.can_record_perf_for_assessment(assessment_id))
        or (assessment_id is null
           and public.can_upload_student_media(student_id))
      )
    )
  ) with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (assessment_id is not null
           and public.can_record_perf_for_assessment(assessment_id))
        or (assessment_id is null
           and public.can_upload_student_media(student_id))
      )
    )
  );

create policy perf_media_write_delete on public.performance_media
  for delete using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (assessment_id is not null
           and public.can_record_perf_for_assessment(assessment_id))
        or (assessment_id is null
           and public.can_upload_student_media(student_id))
      )
    )
  );

-- ----------------------------------------------------------------------------
-- performance_media STORAGE bucket — widen the insert gate to include trainer.
-- Fine-grained student/batch scoping lives on the table row (above); the
-- bucket stays academy-folder scoped, matching the other private buckets.
-- ----------------------------------------------------------------------------
drop policy if exists "perf_media_coach_insert" on storage.objects;

create policy "perf_media_staff_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'performance_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.current_user_role() in (
      'academy_owner', 'academy_admin', 'center_admin',
      'head_coach', 'coach', 'trainer'
    )
  );
