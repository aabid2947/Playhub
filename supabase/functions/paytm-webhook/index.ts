// Paytm callback / webhook. Set as the callbackUrl on initiateTransaction:
//   https://<project-ref>.supabase.co/functions/v1/paytm-webhook?academy=<academy_id>
//
// Security (invariant #6): we do NOT trust the posted body. We take only the
// ORDERID from it, then confirm the outcome against Paytm's Transaction-Status
// API (server-to-server, signed with the academy's own merchant key). A payment
// is recorded only when that API reports TXN_SUCCESS *and* a matching
// payment_attempts row exists, so a forged callback can't fabricate a payment.
// Idempotent via payments.unique_event_id = 'paytm:<orderId>'.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { getPaytmTransactionStatus } from '../_shared/paytm.ts';
import { resolvePaytmCreds } from '../_shared/payment_gateway.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return j({ error: 'missing env' }, 500);

  const academyId = new URL(req.url).searchParams.get('academy');
  if (!academyId) return j({ error: 'academy param required' }, 400);

  // Paytm posts the callback as form-encoded; tolerate JSON too.
  const orderId = await extractOrderId(req);
  if (!orderId) return j({ ok: true, ignored: 'no ORDERID' });

  const admin = createClient(url, serviceKey);

  // The attempt must exist in our DB — otherwise this isn't a transaction we
  // created, so ignore it (don't let an arbitrary orderId drive a payment).
  const { data: attempt } = await admin
    .from('payment_attempts')
    .select('id, invoice_id, academy_id, amount, status')
    .eq('paytm_order_id', orderId)
    .eq('academy_id', academyId)
    .maybeSingle();
  if (!attempt) return j({ ok: true, ignored: 'unknown order' });

  // Confirm with Paytm (authoritative).
  let status;
  try {
    const creds = await resolvePaytmCreds(admin, academyId);
    status = await getPaytmTransactionStatus(creds, orderId);
  } catch (e) {
    return j({ error: (e as Error).message }, 502);
  }

  if (status.resultStatus !== 'TXN_SUCCESS') {
    if (attempt.status !== 'paid') {
      await admin.from('payment_attempts')
        .update({
          status: 'failed',
          failure_reason: status.resultMsg || status.resultStatus,
        })
        .eq('id', attempt.id);
    }
    return j({ ok: true, status: status.resultStatus, order_id: orderId });
  }

  // Need student_id for the payment row.
  const { data: invoice } = await admin
    .from('invoices')
    .select('id, student_id, academy_id')
    .eq('id', attempt.invoice_id)
    .single();
  if (!invoice) return j({ error: 'invoice not found' }, 404);

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

  // 23505 = unique_violation → duplicate callback delivery, already recorded.
  if (payErr && payErr.code !== '23505') {
    return j({ error: payErr.message }, 500);
  }

  await admin.from('payment_attempts')
    .update({ status: 'paid', payment_id: payment?.id ?? null })
    .eq('id', attempt.id);

  return j({ ok: true, event: 'paytm.captured', order_id: orderId });
});

async function extractOrderId(req: Request): Promise<string | null> {
  const ct = req.headers.get('content-type') ?? '';
  try {
    if (ct.includes('application/json')) {
      const body = await req.json();
      return body?.ORDERID ?? body?.orderId ?? body?.body?.orderId ?? null;
    }
    // form-encoded (Paytm's default callback content type)
    const text = await req.text();
    const params = new URLSearchParams(text);
    return params.get('ORDERID') ?? params.get('orderId');
  } catch {
    return null;
  }
}

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
