-- ============================================================================
-- Sprint 4 — chat_attachments storage bucket (private).
--   Layout: <academy_id>/<thread_id>/<message_uuid>.<ext>
--   Read/write gated to thread participants in the same academy.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('chat_attachments', 'chat_attachments', false)
on conflict (id) do nothing;

-- SELECT — top-level folder must equal caller's academy; thread folder
-- (segment 2) must be a thread the caller participates in.
create policy "chat_attachments_member_read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'chat_attachments'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and (
      public.has_admin_or_higher()
      or public.is_thread_participant(((storage.foldername(name))[2])::uuid)
    )
  );

create policy "chat_attachments_member_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'chat_attachments'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.is_thread_participant(((storage.foldername(name))[2])::uuid)
  );

-- Update / delete: only the uploader (owner column on storage.objects).
create policy "chat_attachments_owner_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'chat_attachments'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and owner = auth.uid()
  );

create policy "chat_attachments_owner_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'chat_attachments'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and (owner = auth.uid() or public.has_admin_or_higher())
  );
