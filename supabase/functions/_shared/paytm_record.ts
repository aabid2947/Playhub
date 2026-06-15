// Shared: confirm a Paytm transaction against the authoritative Transaction
// Status API and record the payment idempotently. Used by both paytm-webhook
// (Paytm's server-to-server callback) and verify-paytm-payment (the client
// asking "did it go through?"). Recording money in one place keeps the two
// paths consistent (invariant #6).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { getPaytmTransactionStatus } from './paytm.ts';
import { resolvePaytmCreds } from './payment_gateway.ts';

type Admin = ReturnType<typeof createClient>;

export interface PaytmConfirmResult {
  status: string; // TXN_SUCCESS | TXN_FAILURE | PENDING | unknown | ...
  recorded: boolean;
}

/// Confirms `orderId` for `academyId` and records a payment row on success.
/// Idempotent: a duplicate call (or a duplicate webhook) is a no-op thanks to
/// `payments.unique_event_id = 'paytm:<orderId>'`. Returns the authoritative
/// status. Throws only on unexpected DB/API errors.
export async function confirmAndRecordPaytm(
  admin: Admin,
  academyId: string,
  orderId: string,
): Promise<PaytmConfirmResult> {
  const { data: attempt } = await admin
    .from('payment_attempts')
    .select('id, invoice_id, academy_id, amount, status')
    .eq('paytm_order_id', orderId)
    .eq('academy_id', academyId)
    .maybeSingle();
  if (!attempt) return { status: 'unknown', recorded: false };

  const creds = await resolvePaytmCreds(admin, academyId);
  const status = await getPaytmTransactionStatus(creds, orderId);

  if (status.resultStatus !== 'TXN_SUCCESS') {
    // Only flip to failed if it isn't already settled (don't clobber a paid
    // attempt that a slower call is re-checking).
    if (attempt.status !== 'paid' && status.resultStatus !== 'PENDING') {
      await admin.from('payment_attempts')
        .update({
          status: 'failed',
          failure_reason: status.resultMsg || status.resultStatus,
        })
        .eq('id', attempt.id);
    }
    return { status: status.resultStatus, recorded: false };
  }

  const { data: invoice } = await admin
    .from('invoices')
    .select('id, student_id, academy_id')
    .eq('id', attempt.invoice_id)
    .single();
  if (!invoice) return { status: 'invoice_missing', recorded: false };

  const amount = status.txnAmount != null
    ? Number(status.txnAmount)
    : Number(attempt.amount);

  const { data: payment, error: payErr } = await admin
    .from('payments')
    .insert({
      academy_id: invoice.academy_id,
      invoice_id: invoice.id,
      student_id: invoice.student_id,
      amount,
      method: 'paytm',
      status: 'completed',
      paytm_order_id: orderId,
      paytm_txn_id: status.txnId ?? null,
      unique_event_id: `paytm:${orderId}`,
    })
    .select('id')
    .maybeSingle();

  // 23505 = unique_violation → already recorded by the other path; that's fine.
  if (payErr && payErr.code !== '23505') {
    throw new Error(payErr.message);
  }

  await admin.from('payment_attempts')
    .update({ status: 'paid', payment_id: payment?.id ?? null })
    .eq('id', attempt.id);

  return { status: 'TXN_SUCCESS', recorded: true };
}
