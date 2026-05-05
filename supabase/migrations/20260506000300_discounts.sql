-- ============================================================================
-- Discounts — modeled symmetrically to fees:
--   discount_structures            → templates (sibling 10%, scholarship 50%, …)
--   student_discount_assignments   → per-student (overrides + one-offs)
--   batch_discount_assignments     → batch-wide
--
-- A student-level assignment carries a `stack_with_batch` flag:
--   true  → student-level + batch-level both apply (default)
--   false → only student-level applies; batch-level is suppressed for this
--           student (used for full scholarships / per-student override)
--
-- recur-invoice-generation reads both sources, computes per-discount
-- amounts (pct of base_amount or flat), and inserts a `discount` line
-- item plus updates invoices.discount_amount.
-- ============================================================================

create table public.discount_structures (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,

  name text not null,
  description text,
  type text not null check (type in ('percentage', 'flat')),
  -- value is interpreted per type: percentage 0-100 of base_amount, or flat ₹.
  value numeric(10, 2) not null check (value >= 0),

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_discount_structures_academy
  on public.discount_structures(academy_id);

create trigger trg_discount_structures_updated before update on public.discount_structures
  for each row execute function public.set_updated_at();

-- Per-student assignments
create table public.student_discount_assignments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  discount_structure_id uuid not null references public.discount_structures(id) on delete cascade,

  start_date date not null default current_date,
  end_date date,
  -- When true (default), stacks on top of any batch-level discount.
  -- When false, suppresses batch-level discounts for this student —
  -- only student-level discounts apply (use for full scholarships).
  stack_with_batch boolean not null default true,

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (student_id, discount_structure_id, start_date)
);

create index idx_sda_academy on public.student_discount_assignments(academy_id);
create index idx_sda_student on public.student_discount_assignments(student_id);
create index idx_sda_active
  on public.student_discount_assignments(academy_id, is_active)
  where is_active;

create trigger trg_sda_updated before update on public.student_discount_assignments
  for each row execute function public.set_updated_at();

-- Per-batch assignments
create table public.batch_discount_assignments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  batch_id uuid not null references public.batches(id) on delete cascade,
  discount_structure_id uuid not null references public.discount_structures(id) on delete cascade,

  start_date date not null default current_date,
  end_date date,

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (batch_id, discount_structure_id, start_date)
);

create index idx_bda_academy on public.batch_discount_assignments(academy_id);
create index idx_bda_batch on public.batch_discount_assignments(batch_id);
create index idx_bda_active
  on public.batch_discount_assignments(academy_id, is_active)
  where is_active;

create trigger trg_bda_updated before update on public.batch_discount_assignments
  for each row execute function public.set_updated_at();

-- ============================================================================
-- invoices.discount_amount + recompute generated `amount` column
-- ============================================================================

alter table public.invoices drop column amount;

alter table public.invoices
  add column discount_amount numeric(10, 2) not null default 0
    check (discount_amount >= 0);

alter table public.invoices
  add column amount numeric(10, 2) generated always as
    (base_amount + tax_amount + late_fee_amount - discount_amount) stored;

alter table public.invoices
  add constraint invoices_amount_non_negative check (amount >= 0);

-- ============================================================================
-- RLS — same shape as fee assignments
-- ============================================================================

alter table public.discount_structures           enable row level security;
alter table public.student_discount_assignments  enable row level security;
alter table public.batch_discount_assignments    enable row level security;

create policy ds_academy_read on public.discount_structures
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy ds_admin_insert on public.discount_structures
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy ds_admin_update on public.discount_structures
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy ds_admin_delete on public.discount_structures
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy sda_academy_read on public.student_discount_assignments
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy sda_admin_insert on public.student_discount_assignments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy sda_admin_update on public.student_discount_assignments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy sda_admin_delete on public.student_discount_assignments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy bda_academy_read on public.batch_discount_assignments
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy bda_admin_insert on public.batch_discount_assignments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy bda_admin_update on public.batch_discount_assignments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy bda_admin_delete on public.batch_discount_assignments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- Audit hooks
create trigger trg_audit_discount_structures
  after insert or update or delete on public.discount_structures
  for each row execute function public.write_audit_log();

create trigger trg_audit_student_discount_assignments
  after insert or update or delete on public.student_discount_assignments
  for each row execute function public.write_audit_log();

create trigger trg_audit_batch_discount_assignments
  after insert or update or delete on public.batch_discount_assignments
  for each row execute function public.write_audit_log();
