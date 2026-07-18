// Shared: confirm a Razorpay payment against the authoritative Payments API and
// record it idempotently. Used by verify-razorpay-payment (the client asking
// "did it go through?" right after the sheet closes) so a captured charge is
// recorded even when the async webhook never arrives — which is the failure we
// hit in testing. Mirrors confirmAndRecordPaytm.
//
// Idempotency: payments has a UNIQUE index on razorpay_payment_id, so a row
// already inserted by the webhook (or a duplicate verify call) collides with
// 23505 and is treated as "already recorded". The webhook path is left as-is —
// both converge on the same payment row via that unique key (invariant #6).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { fetchRazorpayPayment } from './razorpay.ts';
import { resolveRazorpayCredsRequireAcademy } from './payment_gateway.ts';

type Admin = ReturnType<typeof createClient>;

export interface RazorpayConfirmResult {
  status: string; // captured | authorized | failed | created | ...
  recorded: boolean;
}

/// Confirms `paymentId`/`orderId` for `academyId` and records a payment row when
/// the charge is `captured`. Returns the authoritative status. Throws only on
/// unexpected DB/API errors.
export async function confirmAndRecordRazorpay(
  admin: Admin,
  academyId: string,
  orderId: string,
  paymentId: string,
): Promise<RazorpayConfirmResult> {
  const { data: attempt } = await admin
    .from('payment_attempts')
    .select('id, invoice_id, academy_id, amount, status')
    .eq('razorpay_order_id', orderId)
    .eq('academy_id', academyId)
    .maybeSingle();
  if (!attempt) return { status: 'unknown', recorded: false };

  const creds = await resolveRazorpayCredsRequireAcademy(admin, academyId);
  const payment = await fetchRazorpayPayment(paymentId, creds);

  // Guard against a payment id that belongs to a different order.
  if (payment.order_id && payment.order_id !== orderId) {
    return { status: 'order_mismatch', recorded: false };
  }

  if (payment.status !== 'captured') {
    if (attempt.status !== 'paid' && payment.status === 'failed') {
      await admin.from('payment_attempts')
        .update({ status: 'failed', failure_reason: payment.status })
        .eq('id', attempt.id);
    }
    return { status: payment.status, recorded: false };
  }

  const { data: invoice } = await admin
    .from('invoices')
    .select('id, student_id, academy_id')
    .eq('id', attempt.invoice_id)
    .single();
  if (!invoice) return { status: 'invoice_missing', recorded: false };

  const { data: row, error: payErr } = await admin
    .from('payments')
    .insert({
      academy_id: invoice.academy_id,
      invoice_id: invoice.id,
      student_id: invoice.student_id,
      amount: payment.amount / 100,
      method: 'razorpay',
      status: 'completed',
      razorpay_order_id: payment.order_id ?? orderId,
      razorpay_payment_id: payment.id,
      unique_event_id: `razorpay:${payment.id}`,
    })
    .select('id')
    .maybeSingle();

  // 23505 = unique_violation → already recorded by the webhook (or a retry).
  if (payErr && payErr.code !== '23505') {
    throw new Error(payErr.message);
  }

  await admin.from('payment_attempts')
    .update({ status: 'paid', payment_id: row?.id ?? null })
    .eq('id', attempt.id);

  return { status: 'captured', recorded: true };
}
