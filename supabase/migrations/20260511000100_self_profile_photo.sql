-- ============================================================================
-- v0.9.4 polish — allow any authenticated user to upload their own
-- profile photo into the `avatars` bucket, scoped to a self-owned subfolder:
--   <academy_id>/users/<own_user_id>/<uuid>.<ext>
--
-- Existing admin-only policies cover the entity slots (students, coaches,
-- academy) and remain unchanged. We layer a self-write policy on top so
-- parents, students, coaches, and trainers can each maintain their own
-- avatar without needing admin involvement.
-- ============================================================================

create policy "avatars_self_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and (storage.foldername(name))[2] = 'users'
    and (storage.foldername(name))[3] = auth.uid()::text
  );

create policy "avatars_self_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and (storage.foldername(name))[2] = 'users'
    and (storage.foldername(name))[3] = auth.uid()::text
  );

create policy "avatars_self_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and (storage.foldername(name))[2] = 'users'
    and (storage.foldername(name))[3] = auth.uid()::text
  );

-- Existing users RLS allows self-update on the row; we just need the
-- profile_photo column to be writable. It already is (no per-column gate),
-- so nothing extra to do at the SQL layer.
