-- ============================================================================
-- Sprint 3 — fee structures + student fee assignments + late-fee policy.
--
-- Fee structures are templates ("Cricket U-15 monthly = ₹2000 + 18% GST,
-- 5-day grace, ₹50/day late"). They're attached to students via
-- `student_fee_assignments`, which is what the recurring-invoice cron
-- iterates over.
-- ============================================================================

-- Late-fee policy controllable per-academy. fee_structures can override.
alter table public.academies
  add column if not exists late_fee_grace_days int not null default 5
    check (late_fee_grace_days >= 0 and late_fee_grace_days <= 60),
  add column if not exists late_fee_policy text not null default 'one_time'
    check (late_fee_policy in ('none', 'one_time', 'daily')),
  add column if not exists invoice_prefix text not null default 'INV';

create table public.fee_structures (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,

  name text not null,
  description text,
  type text not null
    check (type in ('monthly', 'quarterly', 'annual', 'one_time')),

  -- Optional scope: a fee structure can target a sport and/or batch. NULL
  -- on either side means "applies to anyone the admin assigns it to".
  sport text,
  batch_id uuid references public.batches(id) on delete set null,

  base_amount numeric(10, 2) not null check (base_amount >= 0),
  tax_pct numeric(5, 2) not null default 0 check (tax_pct >= 0 and tax_pct <= 100),

  -- Late fee overrides (NULL = inherit from academy)
  late_fee_pct numeric(5, 2) check (late_fee_pct >= 0 and late_fee_pct <= 100),
  late_fee_flat numeric(10, 2) check (late_fee_flat >= 0),
  late_fee_grace_days int check (late_fee_grace_days >= 0 and late_fee_grace_days <= 60),
  late_fee_policy text check (late_fee_policy in ('none', 'one_time', 'daily')),

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_fee_structures_academy on public.fee_structures(academy_id);
create index idx_fee_structures_batch on public.fee_structures(batch_id);

create trigger trg_fee_structures_updated before update on public.fee_structures
  for each row execute function public.set_updated_at();

-- Junction: which fee structure applies to which student, with effective
-- window. The recurring-invoice cron picks rows where today is between
-- start_date and end_date (or end_date is null).
create table public.student_fee_assignments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  fee_structure_id uuid not null references public.fee_structures(id) on delete cascade,

  start_date date not null default current_date,
  end_date date,
  -- For monthly fees, the day-of-month the next invoice should issue. NULL
  -- → use start_date's day-of-month.
  billing_day int check (billing_day between 1 and 28),

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- A student shouldn't have two overlapping active assignments of the
  -- same fee structure. Hard-enforce on (student, fee, active).
  unique (student_id, fee_structure_id, start_date)
);

create index idx_sfa_academy on public.student_fee_assignments(academy_id);
create index idx_sfa_student on public.student_fee_assignments(student_id);
create index idx_sfa_active
  on public.student_fee_assignments(academy_id, is_active)
  where is_active;

create trigger trg_sfa_updated before update on public.student_fee_assignments
  for each row execute function public.set_updated_at();

-- ============================================================================
-- RLS — academy-scoped read; admin-or-higher writes. Per-action split to
-- avoid the `for all` cross-tenant read leak.
-- ============================================================================

alter table public.fee_structures            enable row level security;
alter table public.student_fee_assignments   enable row level security;

create policy fee_structures_academy_read on public.fee_structures
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy fee_structures_admin_insert on public.fee_structures
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy fee_structures_admin_update on public.fee_structures
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy fee_structures_admin_delete on public.fee_structures
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy sfa_academy_read on public.student_fee_assignments
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy sfa_admin_insert on public.student_fee_assignments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy sfa_admin_update on public.student_fee_assignments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy sfa_admin_delete on public.student_fee_assignments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- Audit hooks
create trigger trg_audit_fee_structures
  after insert or update or delete on public.fee_structures
  for each row execute function public.write_audit_log();

create trigger trg_audit_student_fee_assignments
  after insert or update or delete on public.student_fee_assignments
  for each row execute function public.write_audit_log();
