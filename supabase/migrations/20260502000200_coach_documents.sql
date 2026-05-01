-- ============================================================================
-- coach_documents — same shape as student_documents
-- ============================================================================

create table public.coach_documents (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  coach_id uuid not null references public.coaches(id) on delete cascade,

  type text not null
    check (type in ('id_proof', 'qualification', 'certification',
                    'photo', 'contract', 'other')),
  file_path text not null,
  original_filename text,
  mime_type text,
  size_bytes int,

  uploaded_by uuid references public.users(id) on delete set null,
  uploaded_at timestamptz not null default now()
);

create index idx_coach_documents_coach on public.coach_documents(coach_id);
create index idx_coach_documents_academy on public.coach_documents(academy_id);

alter table public.coach_documents enable row level security;

create policy coach_documents_academy_read on public.coach_documents
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy coach_documents_admin_write on public.coach_documents
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- ============================================================================
-- Private storage bucket
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('coach_documents', 'coach_documents', false)
on conflict (id) do nothing;

create policy "coach_docs_member_select"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'coach_documents'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
  );

create policy "coach_docs_admin_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'coach_documents'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );

create policy "coach_docs_admin_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'coach_documents'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );

create policy "coach_docs_admin_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'coach_documents'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_admin_or_higher()
  );
