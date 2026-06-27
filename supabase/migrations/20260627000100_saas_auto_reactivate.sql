-- ============================================================================
-- Subscription enforcement — Phase 3a: auto-reactivate on full payment.
--
-- When a SaaS payment clears the last outstanding invoice for a subscription,
-- flip the subscription (and its academy) back to 'active' + is_active=true so
-- a suspended/past_due academy is unblocked automatically. This is the recovery
-- half of the enforcement loop — it MUST exist before writes are gated so a
-- paying academy is never stranded.
--
-- Pairs with apply_saas_payment() (trg_saas_payment_apply), which marks the
-- invoice 'paid'. Trigger fire order on saas_payments is by name:
--   trg_saas_payment_apply  <  trg_saas_payment_reactivate
-- so the just-paid invoice is already 'paid' when we count outstanding ones.
--
-- Super-admin can also reactivate manually via web-admin (reactivateSubscription
-- action) — e.g. a trial-expired academy that has no invoice to pay against.
-- See SUBSCRIPTION_ENFORCEMENT.md.
-- ============================================================================

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
    -- Only touch rows that were actually blocked (idempotent; never demotes).
    update public.academy_subscriptions
      set status = 'active'
      where id = v_subscription_id
        and status in ('past_due', 'suspended');

    update public.academies
      set subscription_status = 'active',
          is_active = true
      where id = v_academy_id
        and subscription_status in ('past_due', 'suspended');
  end if;

  return new;
end;
$$;

create trigger trg_saas_payment_reactivate
  after insert on public.saas_payments
  for each row execute function public.reactivate_paid_subscription();
