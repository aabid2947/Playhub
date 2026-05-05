-- ============================================================================
-- Replace the bulk-create-many-rows approach with a first-class
-- batch_fee_assignments table.
--
-- Two parallel sources of truth for the recurring-invoice cron:
--   - student_fee_assignments  → student-specific fees (overrides, one-offs)
--   - batch_fee_assignments    → batch-wide fees, apply to every active
--                                 enrollment automatically
--
-- The cron unions both and dedupes by (student, fee_structure, period_start),
-- so a student covered by both only gets one invoice per period.
-- ============================================================================

-- The Sprint-3 RPC that bulk-created student rows is no longer the model.
drop function if exists public.assign_fee_to_batch(uuid, uuid, date, int);

create table public.batch_fee_assignments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  batch_id uuid not null references public.batches(id) on delete cascade,
  fee_structure_id uuid not null references public.fee_structures(id) on delete cascade,

  start_date date not null default current_date,
  end_date date,
  billing_day int check (billing_day between 1 and 28),

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- One assignment of a given fee to a given batch starting on a given date.
  unique (batch_id, fee_structure_id, start_date)
);

create index idx_bfa_academy on public.batch_fee_assignments(academy_id);
create index idx_bfa_batch on public.batch_fee_assignments(batch_id);
create index idx_bfa_active
  on public.batch_fee_assignments(academy_id, is_active)
  where is_active;

create trigger trg_bfa_updated before update on public.batch_fee_assignments
  for each row execute function public.set_updated_at();

-- ============================================================================
-- RLS — same shape as student_fee_assignments
-- ============================================================================

alter table public.batch_fee_assignments enable row level security;

create policy bfa_academy_read on public.batch_fee_assignments
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy bfa_admin_insert on public.batch_fee_assignments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy bfa_admin_update on public.batch_fee_assignments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy bfa_admin_delete on public.batch_fee_assignments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create trigger trg_audit_batch_fee_assignments
  after insert or update or delete on public.batch_fee_assignments
  for each row execute function public.write_audit_log();
