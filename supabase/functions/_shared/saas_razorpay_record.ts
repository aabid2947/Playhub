// Shared: confirm a SaaS Razorpay charge (PlayHub billing the academy) against
// the authoritative Payments API and record it into saas_payments idempotently.
// Used by verify-saas-payment so a captured SaaS charge activates the academy
// even when the async platform webhook never arrives — the failure we hit in
// testing. Mirrors confirmAndRecordRazorpay (the fee-collection equivalent).
//
// SaaS billing ALWAYS uses the PLATFORM Razorpay keys (never a per-academy
// merchant gateway). Idempotency: saas_payments has partial unique indexes on
// BOTH unique_event_id and razorpay_payment_id (20260714000200), so this path
// and the webhook converge on the same row (23505 = already recorded). The
// apply_saas_payment + reactivate_paid_subscription triggers then mark the
// invoice paid and flip the academy to active.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { fetchRazorpayPayment, platformRazorpayCreds } from './razorpay.ts';

type Admin = ReturnType<typeof createClient>;

export interface SaasConfirmResult {
  status: string; // captured | authorized | failed | created | order_mismatch
  recorded: boolean;
}

/// Confirms `paymentId`/`orderId` for a SaaS invoice and records a saas_payments
/// row when the charge is `captured`. Returns the authoritative status. Throws
/// only on unexpected DB/API errors.
export async function confirmAndRecordSaasRazorpay(
  admin: Admin,
  academyId: string,
  saasInvoiceId: string,
  orderId: string,
  paymentId: string,
): Promise<SaasConfirmResult> {
  const creds = platformRazorpayCreds();
  const payment = await fetchRazorpayPayment(paymentId, creds);

  // Guard against a payment id that belongs to a different order.
  if (payment.order_id && payment.order_id !== orderId) {
    return { status: 'order_mismatch', recorded: false };
  }
  if (payment.status !== 'captured') {
    return { status: payment.status, recorded: false };
  }

  const { error } = await admin.from('saas_payments').insert({
    academy_id: academyId,
    saas_invoice_id: saasInvoiceId,
    amount: payment.amount / 100,
    method: 'razorpay',
    razorpay_order_id: payment.order_id ?? orderId,
    razorpay_payment_id: payment.id,
    unique_event_id: `razorpay:${payment.id}`,
  });

  // 23505 = unique_violation → already recorded by the webhook (or a retry).
  if (error && error.code !== '23505') {
    throw new Error(error.message);
  }

  return { status: 'captured', recorded: true };
}
