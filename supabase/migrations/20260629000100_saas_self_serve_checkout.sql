-- ============================================================================
-- Owner self-serve SaaS checkout — the deferred "Phase 6" from
-- SUBSCRIPTION_ENFORCEMENT.md. Lets a new academy owner choose, at signup,
-- between a 14-day free trial and paying ₹100/month via Razorpay (platform
-- gateway). Three pieces here:
--
--   1. A ₹100 'starter' subscription plan (the self-serve monthly price).
--   2. saas_payments.unique_event_id — idempotency key for the Razorpay webhook
--      (mirrors payments.unique_event_id), so a duplicate webhook delivery can't
--      double-record a SaaS payment (invariant #6).
--   3. Widen reactivate_paid_subscription() to also convert a paying TRIAL
--      subscription → active (today it only un-freezes past_due/suspended; a
--      trial paying its first invoice was never activated — the missing
--      trial→active conversion). On a trial conversion it also rolls the billing
--      period to a fresh month and clears trial_ends_at.
--
-- The order is created + the saas_invoice issued by the create-saas-order edge
-- function (platform Razorpay keys — PlayHub bills the academy, NOT the
-- academy's own merchant gateway); the platform razorpay-webhook records the
-- saas_payment, and the trigger below activates the academy.
-- ============================================================================

-- 1. The self-serve monthly plan. ₹100 is a launch/placeholder price — change it
--    by updating this row (the checkout reads the plan's monthly_price).
insert into public.subscription_plans (
  code, name, description, monthly_price, yearly_price,
  max_students, max_coaches, max_centers, features
)
values
  ('starter', 'Starter', 'Self-serve monthly plan', 100, null,
   50, 5, 1, '{"reports": false, "events": true}'::jsonb)
on conflict (code) do nothing;

-- 2. Idempotency key for SaaS webhook recording.
alter table public.saas_payments
  add column if not exists unique_event_id text;

create unique index if not exists uq_saas_payments_event
  on public.saas_payments(unique_event_id)
  where unique_event_id is not null;

-- 3. Trial → active conversion (plus the existing past_due/suspended recovery).
create or replace function public.reactivate_paid_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subscription_id uuid;
  v_academy_id uuid;
  v_outstanding int;
  v_status public.subscription_status;
begin
  -- Resolve the subscription + academy from the invoice this payment hit.
  select si.subscription_id, si.academy_id
    into v_subscription_id, v_academy_id
  from public.saas_invoices si
  where si.id = new.saas_invoice_id;

  if v_subscription_id is null then
    return new;
  end if;

  -- Any invoice for this subscription still outstanding?
  select count(*)
    into v_outstanding
  from public.saas_invoices
  where subscription_id = v_subscription_id
    and status not in ('paid', 'cancelled');

  if v_outstanding = 0 then
    select status into v_status
    from public.academy_subscriptions
    where id = v_subscription_id;

    if v_status = 'trial' then
      -- A trial owner paid their first invoice → start a fresh monthly cycle.
      update public.academy_subscriptions
        set status = 'active',
            current_period_start = now(),
            current_period_end = now() + interval '1 month',
            trial_ends_at = null
        where id = v_subscription_id;
    else
      -- Recovery from a freeze (idempotent; never demotes).
      update public.academy_subscriptions
        set status = 'active'
        where id = v_subscription_id
          and status in ('past_due', 'suspended');
    end if;

    update public.academies
      set subscription_status = 'active',
          is_active = true
      where id = v_academy_id
        and subscription_status in ('trial', 'past_due', 'suspended');
  end if;

  return new;
end;
$$;
