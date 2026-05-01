-- ============================================================================
-- Sprint 1 — Storage: `avatars` bucket
--   Layout: <academy_id>/<entity>/<uuid>.<ext>
--     entity ∈ {students, coaches, academy}
--   Public read (avatars are non-sensitive); writes gated by RLS.
--   Sensitive documents (ID proofs, medical certs) get their own private
--   bucket in a later migration.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- INSERT: must be admin-or-higher in the academy whose id is the top-level
-- folder of the upload path.
create policy "avatars_admin_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );

create policy "avatars_admin_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );

create policy "avatars_admin_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );

-- SELECT is implicit because the bucket is public; no policy required.
