-- ============================================================================
-- Sprint 1 — student_documents (ID proofs, medical certs, etc.)
-- ============================================================================

create table public.student_documents (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,

  type text not null
    check (type in ('id_proof', 'medical_certificate',
                    'birth_certificate', 'photo', 'other')),
  file_path text not null,            -- key inside the private bucket
  original_filename text,
  mime_type text,
  size_bytes int,

  uploaded_by uuid references public.users(id) on delete set null,
  uploaded_at timestamptz not null default now()
);

create index idx_student_documents_student on public.student_documents(student_id);
create index idx_student_documents_academy on public.student_documents(academy_id);

alter table public.student_documents enable row level security;

create policy student_documents_academy_read on public.student_documents
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy student_documents_admin_write on public.student_documents
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- ============================================================================
-- Private bucket. Reads use signed URLs, never public ones.
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('student_documents', 'student_documents', false)
on conflict (id) do nothing;

-- SELECT (used to generate signed URLs from the client SDK)
create policy "student_docs_member_select"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'student_documents'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
  );

create policy "student_docs_admin_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'student_documents'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );

create policy "student_docs_admin_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'student_documents'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );

create policy "student_docs_admin_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'student_documents'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );
