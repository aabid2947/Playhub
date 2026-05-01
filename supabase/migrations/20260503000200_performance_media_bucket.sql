-- ============================================================================
-- Sprint 2 — performance_media private storage bucket
--
-- Holds photo/video evidence per assessment. Path layout:
--   <academy_id>/assessments/<assessment_id>/<filename>
-- Same-academy folder pattern as student_documents/coach_documents.
-- Reads use signed URLs from the client SDK.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('performance_media', 'performance_media', false)
on conflict (id) do nothing;

create policy "perf_media_member_select"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'performance_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
  );

create policy "perf_media_coach_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'performance_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_coach_or_higher()
  );

create policy "perf_media_coach_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'performance_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_coach_or_higher()
  );

create policy "perf_media_coach_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'performance_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_coach_or_higher()
  );
