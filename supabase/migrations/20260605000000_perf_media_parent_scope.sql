-- ============================================================================
-- Narrow the performance_media STORAGE read policy so it mirrors the table-
-- level parent/student scoping added in 20260508000000_parent_links.sql.
--
-- Before: any academy member could SELECT any performance_media object in
-- their academy (academy-wide), relying on the table RLS to hide the *rows*
-- (and therefore the paths) of other children. This tightens the file layer
-- so a parent/student can only fetch the signed URL for media belonging to a
-- student they're allowed to see — making RLS, not row-discovery, the gate
-- (per the project's security model).
--
-- Staff roles (academy_owner / academy_admin / center_admin / head_coach /
-- coach / trainer) keep their existing academy-wide read. The insert / update
-- / delete policies are unchanged (coach-or-higher only).
-- ============================================================================

-- The storage policy joins storage.objects.name -> performance_media.file_path.
-- file_path is the full object key (<academy_id>/assessments/<assessment_id>/
-- <uuid>.<ext>) that StorageService stores verbatim; index that lookup.
create index if not exists idx_perf_media_file_path
  on public.performance_media (file_path);

drop policy if exists "perf_media_member_select" on storage.objects;

create policy "perf_media_member_select"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'performance_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and (
      -- staff: unchanged academy-wide visibility
      public.current_user_role() not in ('parent', 'student')
      -- parent/student: only files for a student they're allowed to see.
      -- The subquery runs under the caller's RLS, so for a parent it already
      -- only contains their own children's rows.
      or exists (
        select 1
        from public.performance_media pm
        where pm.file_path = storage.objects.name
          and public.parent_can_see_student(pm.student_id)
      )
    )
  );
