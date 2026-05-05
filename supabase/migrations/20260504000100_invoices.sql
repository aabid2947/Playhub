-- ============================================================================
-- Sprint 3 — invoices + invoice line items + per-academy invoice number.
--
-- Invoice numbering is per-academy: a counter row in academy_invoice_counters
-- is incremented inside `next_invoice_number(academy_id)`, which is the
-- only sanctioned way to allocate a number. Using a sequence per academy
-- would also work but doesn't survive academy deletion cleanly.
-- ============================================================================

create table public.academy_invoice_counters (
  academy_id uuid primary key references public.academies(id) on delete cascade,
  next_value bigint not null default 1
);

create or replace function public.next_invoice_number(p_academy_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n bigint;
  v_prefix text;
begin
  insert into public.academy_invoice_counters (academy_id, next_value)
  values (p_academy_id, 1)
  on conflict (academy_id) do nothing;

  update public.academy_invoice_counters
    set next_value = next_value + 1
    where academy_id = p_academy_id
    returning next_value - 1 into v_n;

  select coalesce(invoice_prefix, 'INV') into v_prefix
    from public.academies where id = p_academy_id;

  return v_prefix || '-' || lpad(v_n::text, 6, '0');
end;
$$;

-- ============================================================================
-- invoices
-- ============================================================================

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  fee_structure_id uuid references public.fee_structures(id) on delete set null,

  invoice_number text not null,                    -- per-academy unique
  status text not null default 'issued'
    check (status in ('draft', 'issued', 'partial', 'paid', 'overdue', 'cancelled')),

  -- Period the invoice covers (for monthly etc.). Optional for one-time.
  period_start date,
  period_end date,
  issued_at timestamptz not null default now(),
  due_date date not null,

  base_amount numeric(10, 2) not null check (base_amount >= 0),
  tax_amount  numeric(10, 2) not null default 0 check (tax_amount >= 0),
  late_fee_amount numeric(10, 2) not null default 0 check (late_fee_amount >= 0),
  amount      numeric(10, 2) generated always as
                (base_amount + tax_amount + late_fee_amount) stored,
  amount_paid numeric(10, 2) not null default 0 check (amount_paid >= 0),

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (academy_id, invoice_number)
);

create index idx_invoices_academy_status_due
  on public.invoices(academy_id, status, due_date);
create index idx_invoices_student_due
  on public.invoices(student_id, due_date desc);

create trigger trg_invoices_updated before update on public.invoices
  for each row execute function public.set_updated_at();

-- ============================================================================
-- invoice_line_items — one row per fee component (base, tax, late_fee,
-- discount, custom). Useful for receipt rendering and reconciliation.
-- ============================================================================

create table public.invoice_line_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  academy_id uuid not null references public.academies(id) on delete cascade,

  kind text not null
    check (kind in ('base', 'tax', 'late_fee', 'discount', 'adjustment')),
  description text not null,
  quantity numeric(10, 2) not null default 1 check (quantity > 0),
  unit_amount numeric(10, 2) not null,
  total_amount numeric(10, 2) generated always as
    (round(quantity * unit_amount, 2)) stored,

  created_at timestamptz not null default now()
);

create index idx_invoice_lines_invoice on public.invoice_line_items(invoice_id);
create index idx_invoice_lines_academy on public.invoice_line_items(academy_id);

-- ============================================================================
-- RLS
--
-- Reads: any authenticated user in the same academy (parent/student
-- read-narrowing lands when parent_links arrives). Writes: admin-or-higher,
-- per-action split to keep tenant filter explicit on each policy.
-- ============================================================================

alter table public.academy_invoice_counters enable row level security;
alter table public.invoices                 enable row level security;
alter table public.invoice_line_items       enable row level security;

-- counters: no policies for app callers — only the SECURITY DEFINER
-- function `next_invoice_number` writes. Reads are unnecessary from app.
revoke all on public.academy_invoice_counters from public;
grant execute on function public.next_invoice_number(uuid) to authenticated;

create policy invoices_academy_read on public.invoices
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy invoices_admin_insert on public.invoices
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy invoices_admin_update on public.invoices
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy invoices_admin_delete on public.invoices
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy invoice_lines_academy_read on public.invoice_line_items
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy invoice_lines_admin_insert on public.invoice_line_items
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy invoice_lines_admin_update on public.invoice_line_items
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy invoice_lines_admin_delete on public.invoice_line_items
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- Audit hooks
create trigger trg_audit_invoices
  after insert or update or delete on public.invoices
  for each row execute function public.write_audit_log();

create trigger trg_audit_invoice_line_items
  after insert or update or delete on public.invoice_line_items
  for each row execute function public.write_audit_log();
