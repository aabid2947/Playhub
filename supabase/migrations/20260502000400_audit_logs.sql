-- ============================================================================
-- audit_logs — write-only history of insert/update/delete on tenant tables.
--
-- Filled by a trigger function attached to every tenant-data table. Reads
-- are restricted to admins of the same academy (super_admin sees all).
-- The trigger runs as SECURITY DEFINER so it can insert past the RLS gates;
-- there are no INSERT/UPDATE/DELETE policies, so app-level writes are blocked.
-- ============================================================================

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid references public.academies(id) on delete set null,
  user_id uuid references public.users(id) on delete set null,
  action text not null check (action in ('insert', 'update', 'delete')),
  entity_type text not null,
  entity_id uuid,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);

create index idx_audit_logs_academy_created
  on public.audit_logs(academy_id, created_at desc);
create index idx_audit_logs_entity
  on public.audit_logs(entity_type, entity_id);

-- ============================================================================
-- Generic writer used by every per-table trigger below.
-- ============================================================================
create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action text;
  v_before jsonb;
  v_after jsonb;
  v_entity_id uuid;
  v_academy_id uuid;
begin
  if TG_OP = 'INSERT' then
    v_action := 'insert';
    v_after := to_jsonb(new);
    v_entity_id := nullif(v_after->>'id', '')::uuid;
  elsif TG_OP = 'UPDATE' then
    v_action := 'update';
    v_before := to_jsonb(old);
    v_after := to_jsonb(new);
    v_entity_id := nullif(v_after->>'id', '')::uuid;
  else
    v_action := 'delete';
    v_before := to_jsonb(old);
    v_entity_id := nullif(v_before->>'id', '')::uuid;
  end if;

  -- Resolve academy_id:
  --   - tables with an academy_id column → take it from the row
  --   - the academies table itself → use its own id
  --   - users table → academy_id is on the row when set
  v_academy_id := nullif(coalesce(v_after, v_before)->>'academy_id', '')::uuid;
  if v_academy_id is null and TG_TABLE_NAME = 'academies' then
    v_academy_id := v_entity_id;
  end if;

  insert into public.audit_logs (
    academy_id, user_id, action, entity_type, entity_id, before, after
  ) values (
    v_academy_id,
    auth.uid(),
    v_action,
    TG_TABLE_NAME,
    v_entity_id,
    v_before,
    v_after
  );

  return coalesce(new, old);
end;
$$;

-- ============================================================================
-- Attach to every tenant-data table.
-- ============================================================================
create trigger trg_audit_academies
  after insert or update or delete on public.academies
  for each row execute function public.write_audit_log();

create trigger trg_audit_centers
  after insert or update or delete on public.centers
  for each row execute function public.write_audit_log();

create trigger trg_audit_users
  after insert or update or delete on public.users
  for each row execute function public.write_audit_log();

create trigger trg_audit_students
  after insert or update or delete on public.students
  for each row execute function public.write_audit_log();

create trigger trg_audit_coaches
  after insert or update or delete on public.coaches
  for each row execute function public.write_audit_log();

create trigger trg_audit_batches
  after insert or update or delete on public.batches
  for each row execute function public.write_audit_log();

create trigger trg_audit_batch_enrollments
  after insert or update or delete on public.batch_enrollments
  for each row execute function public.write_audit_log();

create trigger trg_audit_student_documents
  after insert or update or delete on public.student_documents
  for each row execute function public.write_audit_log();

create trigger trg_audit_coach_documents
  after insert or update or delete on public.coach_documents
  for each row execute function public.write_audit_log();

-- ============================================================================
-- RLS — read-only for admins of the same academy. No write policies, so
-- direct inserts via the API fail; only the SECURITY DEFINER trigger writes.
-- ============================================================================
alter table public.audit_logs enable row level security;

create policy audit_logs_admin_read on public.audit_logs
  for select using (
    public.is_super_admin()
    or (
      academy_id is not null
      and academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
  );
