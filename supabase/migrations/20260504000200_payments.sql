-- ============================================================================
-- Sprint 3 — payments + payment_attempts + refunds + invoice status sync.
--
-- A payment is a confirmed receipt of money. Razorpay payments insert
-- here only after the webhook verifies the signature. Cash/cheque
-- payments are inserted directly by admins.
--
-- payment_attempts tracks each Razorpay order attempt for retry
-- visibility (PLAN: 3× auto-retry on failure with backoff).
-- ============================================================================

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,

  amount numeric(10, 2) not null check (amount > 0),
  method text not null
    check (method in ('razorpay', 'cash', 'cheque', 'bank_transfer', 'upi_manual')),
  status text not null default 'completed'
    check (status in ('completed', 'pending', 'failed', 'refunded', 'partially_refunded')),

  -- Razorpay correlation IDs (NULL for offline methods).
  razorpay_order_id text,
  razorpay_payment_id text,
  razorpay_signature text,

  -- Idempotency: webhook may deliver the same event twice. Composite
  -- unique stops the second insert.
  unique_event_id text,

  recorded_by uuid references public.users(id) on delete set null,
  paid_at timestamptz not null default now(),
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index uniq_payments_razorpay_payment_id
  on public.payments(razorpay_payment_id)
  where razorpay_payment_id is not null;
create unique index uniq_payments_unique_event_id
  on public.payments(unique_event_id)
  where unique_event_id is not null;
create index idx_payments_invoice on public.payments(invoice_id);
create index idx_payments_academy_paid_at
  on public.payments(academy_id, paid_at desc);
create index idx_payments_student on public.payments(student_id);

create trigger trg_payments_updated before update on public.payments
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- payment_attempts — one row per Razorpay order created. PLAN.md decision:
-- 3× auto-retry on failure with backoff. attempt_number is 1..3.
-- ----------------------------------------------------------------------------

create table public.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,

  attempt_number int not null default 1 check (attempt_number between 1 and 3),
  razorpay_order_id text not null,
  amount numeric(10, 2) not null check (amount > 0),
  status text not null default 'created'
    check (status in ('created', 'attempted', 'paid', 'failed', 'expired')),
  failure_reason text,
  -- Linked payment row once Razorpay confirms.
  payment_id uuid references public.payments(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index uniq_attempts_order on public.payment_attempts(razorpay_order_id);
create index idx_attempts_invoice on public.payment_attempts(invoice_id);

create trigger trg_attempts_updated before update on public.payment_attempts
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- refunds
-- ----------------------------------------------------------------------------

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  payment_id uuid not null references public.payments(id) on delete cascade,

  amount numeric(10, 2) not null check (amount > 0),
  reason text,
  status text not null default 'pending'
    check (status in ('pending', 'processed', 'failed')),
  razorpay_refund_id text,
  approved_by uuid references public.users(id) on delete set null,
  processed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index uniq_refund_razorpay_id
  on public.refunds(razorpay_refund_id)
  where razorpay_refund_id is not null;
create index idx_refunds_payment on public.refunds(payment_id);
create index idx_refunds_academy on public.refunds(academy_id);

create trigger trg_refunds_updated before update on public.refunds
  for each row execute function public.set_updated_at();

-- ============================================================================
-- Trigger: keep invoices.amount_paid + status in sync as payments land.
--
-- Every change to a payment row (insert/update/delete) recomputes the
-- parent invoice's amount_paid from the SUM of its non-failed payments
-- minus the SUM of its processed refunds, and flips status to
--   'paid'    when amount_paid >= amount
--   'partial' when amount_paid > 0 and < amount
--   keeps current 'overdue' / 'issued' otherwise.
-- ============================================================================

create or replace function public.sync_invoice_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice uuid;
  v_paid numeric(10, 2);
  v_total numeric(10, 2);
  v_status text;
begin
  v_invoice := coalesce(new.invoice_id, old.invoice_id);
  if v_invoice is null then
    return coalesce(new, old);
  end if;

  select coalesce(sum(p.amount), 0)
       - coalesce((
           select sum(r.amount)
           from public.refunds r
           where r.payment_id in (
             select id from public.payments where invoice_id = v_invoice
           ) and r.status = 'processed'
         ), 0)
    into v_paid
    from public.payments p
    where p.invoice_id = v_invoice
      and p.status in ('completed', 'partially_refunded');

  select amount, status into v_total, v_status
    from public.invoices where id = v_invoice;

  update public.invoices
    set amount_paid = v_paid,
        status = case
          when v_paid >= v_total then 'paid'
          when v_paid > 0 then 'partial'
          when v_status in ('paid', 'partial') then 'issued'
          else v_status
        end
    where id = v_invoice;

  return coalesce(new, old);
end;
$$;

create trigger trg_payments_sync_invoice
  after insert or update or delete on public.payments
  for each row execute function public.sync_invoice_paid_status();

-- Refund sync: a processed refund must also re-evaluate the parent invoice.
create or replace function public.sync_invoice_on_refund()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice uuid;
begin
  select invoice_id into v_invoice
    from public.payments
    where id = coalesce(new.payment_id, old.payment_id);
  if v_invoice is null then
    return coalesce(new, old);
  end if;

  -- Reuse the same logic as sync_invoice_paid_status by touching the
  -- payment row (no-op update).
  update public.payments
    set updated_at = now()
    where id = coalesce(new.payment_id, old.payment_id);

  return coalesce(new, old);
end;
$$;

create trigger trg_refunds_sync_invoice
  after insert or update or delete on public.refunds
  for each row execute function public.sync_invoice_on_refund();

-- ============================================================================
-- RLS — academy-scoped read; admin writes for refunds, manual payments.
-- Razorpay-driven payment inserts come through the webhook function which
-- runs as service-role and bypasses RLS.
-- ============================================================================

alter table public.payments         enable row level security;
alter table public.payment_attempts enable row level security;
alter table public.refunds          enable row level security;

create policy payments_academy_read on public.payments
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy payments_admin_insert on public.payments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy payments_admin_update on public.payments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy payments_admin_delete on public.payments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy attempts_academy_read on public.payment_attempts
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

-- Inserts/updates on attempts come from the order-creation Edge Function
-- (service role). No app-layer write policy.

create policy refunds_academy_read on public.refunds
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy refunds_admin_insert on public.refunds
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy refunds_admin_update on public.refunds
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- Audit hooks
create trigger trg_audit_payments
  after insert or update or delete on public.payments
  for each row execute function public.write_audit_log();

create trigger trg_audit_payment_attempts
  after insert or update or delete on public.payment_attempts
  for each row execute function public.write_audit_log();

create trigger trg_audit_refunds
  after insert or update or delete on public.refunds
  for each row execute function public.write_audit_log();
