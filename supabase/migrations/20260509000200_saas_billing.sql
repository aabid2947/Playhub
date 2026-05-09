-- ============================================================================
-- Sprint 5 — SaaS billing: how PlayHub charges academies for the platform.
--
-- This sits beside the per-student `invoices` table; saas_invoices are
-- platform-billed-to-academy. Tables:
--
--   subscription_plans      — Basic / Pro / Enterprise
--   academy_subscriptions   — one row per academy; current plan + status
--   saas_invoices           — monthly invoice issued to the academy
--   saas_payments           — payments against saas_invoices
--
-- Plans + subscriptions are visible to the academy owner; super_admin manages
-- plan rows. Invoices/payments are visible to the academy owner + super_admin.
-- The `recur-saas-billing` Edge Function generates invoices on renewal and
-- `subscription-grace-period-check` flips status to suspended when overdue.
-- ============================================================================

create type public.saas_invoice_status as enum (
  'issued',
  'paid',
  'past_due',
  'cancelled'
);

create type public.saas_payment_method as enum (
  'razorpay',
  'bank_transfer',
  'manual',
  'free'
);

create table public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,           -- 'basic' / 'pro' / 'enterprise' / custom
  name text not null,
  description text,

  monthly_price numeric(10, 2) not null check (monthly_price >= 0),
  yearly_price numeric(10, 2) check (yearly_price is null or yearly_price >= 0),
  currency text not null default 'INR',

  -- Soft caps (UI hints; real enforcement TBD in v1.1):
  max_students int,
  max_coaches int,
  max_centers int,
  features jsonb not null default '{}'::jsonb,

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_sub_plans_updated before update on public.subscription_plans
  for each row execute function public.set_updated_at();

create table public.academy_subscriptions (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null unique references public.academies(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id) on delete restrict,

  status public.subscription_status not null default 'trial',
  billing_cycle text not null default 'monthly'
    check (billing_cycle in ('monthly', 'yearly')),

  current_period_start timestamptz not null default now(),
  current_period_end timestamptz not null default (now() + interval '1 month'),
  trial_ends_at timestamptz,

  -- Razorpay subscription bookkeeping (auto-debit, optional).
  razorpay_subscription_id text,
  razorpay_customer_id text,

  cancelled_at timestamptz,
  cancellation_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_acad_subs_status on public.academy_subscriptions(status);
create index idx_acad_subs_period_end on public.academy_subscriptions(current_period_end);

create trigger trg_acad_subs_updated before update on public.academy_subscriptions
  for each row execute function public.set_updated_at();

-- ============================================================================
-- saas_invoices — what PlayHub bills the academy each cycle.
-- ============================================================================

create table public.saas_invoices (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  subscription_id uuid not null references public.academy_subscriptions(id) on delete cascade,

  invoice_number text not null unique, -- global; not per-academy

  status public.saas_invoice_status not null default 'issued',
  period_start timestamptz not null,
  period_end timestamptz not null,
  issued_at timestamptz not null default now(),
  due_date date not null,
  paid_at timestamptz,

  amount numeric(10, 2) not null check (amount >= 0),
  tax_amount numeric(10, 2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(10, 2) generated always as (amount + tax_amount) stored,
  amount_paid numeric(10, 2) not null default 0 check (amount_paid >= 0),
  currency text not null default 'INR',

  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_saas_invoices_academy on public.saas_invoices(academy_id, issued_at desc);
create index idx_saas_invoices_status on public.saas_invoices(status, due_date);

create trigger trg_saas_inv_updated before update on public.saas_invoices
  for each row execute function public.set_updated_at();

-- ============================================================================
-- saas_payments — payments against saas_invoices.
-- ============================================================================

create table public.saas_payments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  saas_invoice_id uuid not null references public.saas_invoices(id) on delete cascade,

  amount numeric(10, 2) not null check (amount > 0),
  method public.saas_payment_method not null,
  paid_at timestamptz not null default now(),

  razorpay_payment_id text,
  razorpay_order_id text,
  razorpay_signature text,

  reference text,
  notes text,
  created_at timestamptz not null default now()
);

create index idx_saas_payments_invoice on public.saas_payments(saas_invoice_id);
create index idx_saas_payments_academy on public.saas_payments(academy_id, paid_at desc);

-- Sync amount_paid + status on saas_invoices when a payment lands.

create or replace function public.apply_saas_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric(10, 2);
  v_paid numeric(10, 2);
begin
  update public.saas_invoices
    set amount_paid = amount_paid + new.amount
    where id = new.saas_invoice_id
    returning total_amount, amount_paid into v_total, v_paid;

  if v_paid >= v_total then
    update public.saas_invoices
      set status = 'paid', paid_at = coalesce(paid_at, new.paid_at)
      where id = new.saas_invoice_id;
  end if;

  return new;
end;
$$;

create trigger trg_saas_payment_apply
  after insert on public.saas_payments
  for each row execute function public.apply_saas_payment();

-- ============================================================================
-- Seed default plans. These are global (not per-academy) and managed by
-- super_admin; using upsert by code so reruns are safe.
-- ============================================================================

insert into public.subscription_plans (
  code, name, description, monthly_price, yearly_price,
  max_students, max_coaches, max_centers, features
)
values
  ('basic', 'Basic', 'Single center, up to 100 students', 1499, 14999,
   100, 5, 1, '{"reports": false, "events": true}'::jsonb),
  ('pro', 'Pro', 'Multi-center, up to 500 students',     3999, 39999,
   500, 25, 5, '{"reports": true,  "events": true}'::jsonb),
  ('enterprise', 'Enterprise', 'Unlimited; priority support', 9999, 99999,
   null, null, null, '{"reports": true,  "events": true, "priority_support": true}'::jsonb)
on conflict (code) do nothing;

-- ============================================================================
-- RLS
--   subscription_plans: readable by any authenticated user (so the upgrade
--     page can show plan cards); writable only by super_admin.
--   academy_subscriptions / saas_invoices / saas_payments: readable by the
--     academy owner + super_admin; writes only by super_admin (or service
--     role via Edge Functions).
-- ============================================================================

alter table public.subscription_plans     enable row level security;
alter table public.academy_subscriptions  enable row level security;
alter table public.saas_invoices          enable row level security;
alter table public.saas_payments          enable row level security;

create policy plans_authenticated_read on public.subscription_plans
  for select to authenticated using (true);

create policy plans_super_admin_write on public.subscription_plans
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create policy acad_subs_owner_read on public.academy_subscriptions
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in ('academy_owner', 'academy_admin')
    )
  );

create policy acad_subs_super_admin_write on public.academy_subscriptions
  for all using (public.is_super_admin())
  with check (public.is_super_admin());

create policy saas_invoices_owner_read on public.saas_invoices
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in ('academy_owner', 'academy_admin')
    )
  );

create policy saas_invoices_super_admin_write on public.saas_invoices
  for all using (public.is_super_admin())
  with check (public.is_super_admin());

create policy saas_payments_owner_read on public.saas_payments
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in ('academy_owner', 'academy_admin')
    )
  );

create policy saas_payments_super_admin_write on public.saas_payments
  for all using (public.is_super_admin())
  with check (public.is_super_admin());

-- Audit hooks
create trigger trg_audit_subscription_plans
  after insert or update or delete on public.subscription_plans
  for each row execute function public.write_audit_log();

create trigger trg_audit_academy_subscriptions
  after insert or update or delete on public.academy_subscriptions
  for each row execute function public.write_audit_log();

create trigger trg_audit_saas_invoices
  after insert or update or delete on public.saas_invoices
  for each row execute function public.write_audit_log();

create trigger trg_audit_saas_payments
  after insert or update or delete on public.saas_payments
  for each row execute function public.write_audit_log();

-- ============================================================================
-- Backfill: every existing academy gets a Basic subscription row, mirroring
-- the academy.subscription_status (trial by default) so the upgrade UI has
-- something to render. New academies get one via bootstrap_owner_academy
-- (which we extend below).
-- ============================================================================

insert into public.academy_subscriptions (
  academy_id, plan_id, status, current_period_start, current_period_end, trial_ends_at
)
select
  a.id,
  (select id from public.subscription_plans where code = 'basic'),
  a.subscription_status,
  now(),
  coalesce(a.trial_ends_at, now() + interval '1 month'),
  a.trial_ends_at
from public.academies a
left join public.academy_subscriptions s on s.academy_id = a.id
where s.id is null;
