-- ============================================================================
-- SaaS verify-on-return: make the client-verify path and the async platform
-- webhook converge on ONE saas_payments row.
--
-- saas_payments had a UNIQUE only on unique_event_id, but the two record paths
-- use DIFFERENT unique_event_id values — the webhook uses the Razorpay EVENT id,
-- while verify-saas-payment uses 'razorpay:<payment_id>' (it never sees an event
-- id). Without a second key they would DOUBLE-record the same capture.
--
-- Add a partial unique index on razorpay_payment_id (mirrors public.payments) so
-- both paths collide on 23505 and a captured SaaS charge is recorded exactly
-- once (invariant #6). Manual saas_payments with a null razorpay_payment_id are
-- unaffected (partial index).
-- ============================================================================

create unique index if not exists uq_saas_payments_rzp_payment
  on public.saas_payments (razorpay_payment_id)
  where razorpay_payment_id is not null;
