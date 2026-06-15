-- ============================================================================
-- Paytm payment support — extends the payments / payment_attempts schema so the
-- same flow that records Razorpay receipts also records Paytm ones.
--
-- See 20260615000000_academy_payment_gateways.sql for per-academy credentials,
-- and supabase/functions/{create-payment-order,paytm-webhook} for the runtime.
--
-- Recording stays idempotent + verified (invariant #6): the paytm-webhook
-- confirms each txn against Paytm's Transaction Status API before inserting,
-- and dedupes on payments.unique_event_id (set to 'paytm:<orderId>').
-- ============================================================================

-- 'paytm' becomes a valid payment method (method is a CHECK, not an enum).
alter table public.payments
  drop constraint payments_method_check,
  add constraint payments_method_check
    check (method in ('razorpay', 'paytm', 'cash', 'cheque', 'bank_transfer', 'upi_manual'));

-- Paytm correlation IDs (NULL for non-Paytm payments), mirroring the
-- razorpay_* columns.
alter table public.payments
  add column if not exists paytm_order_id text,
  add column if not exists paytm_txn_id text;

-- payment_attempts now tracks which gateway each attempt used. razorpay_order_id
-- becomes nullable (Paytm attempts carry a paytm_order_id instead); the 3-retry
-- cap (attempt_number 1..3) and per-invoice counting are provider-agnostic.
alter table public.payment_attempts
  add column if not exists provider text not null default 'razorpay'
    check (provider in ('razorpay', 'paytm')),
  add column if not exists paytm_order_id text,
  alter column razorpay_order_id drop not null;

create unique index if not exists uniq_attempts_paytm_order
  on public.payment_attempts(paytm_order_id)
  where paytm_order_id is not null;
