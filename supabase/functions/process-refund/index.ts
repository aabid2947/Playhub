// Admin-triggered: refund a Razorpay payment (or record a manual refund
// for cash/cheque payments). Body: { payment_id, amount, reason? }.
//
// Razorpay payments call the refund API. Manual-method payments just
// insert a 'processed' refund row, which the trigger uses to recompute
// the invoice's amount_paid + status.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { refundRazorpayPayment } from '../_shared/razorpay.ts';
import { resolveRazorpayCreds } from '../_shared/payment_gateway.ts';

interface Body { payment_id: string; amount: number; reason?: string }

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const auth = req.headers.get('authorization') ?? '';
  if (!auth.toLowerCase().startsWith('bearer ')) {
    return j({ error: 'unauthorised' }, 401);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return j({ error: 'missing env' }, 500);

  const body = await req.json().catch(() => null) as Body | null;
  if (!body?.payment_id || !body?.amount) {
    return j({ error: 'payment_id and amount required' }, 400);
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { authorization: auth } },
  });
  const { data: me } = await caller
    .from('users').select('id, role, academy_id').single();
  if (!me) return j({ error: 'no profile' }, 401);
  if (!['super_admin', 'academy_owner', 'academy_admin'].includes(me.role)) {
    return j({ error: 'forbidden' }, 403);
  }

  const admin = createClient(url, serviceKey);
  const { data: payment, error: pErr } = await admin
    .from('payments')
    .select('id, academy_id, amount, method, razorpay_payment_id, status')
    .eq('id', body.payment_id)
    .single();
  if (pErr || !payment) return j({ error: 'payment not found' }, 404);
  if (payment.academy_id !== me.academy_id && me.role !== 'super_admin') {
    return j({ error: 'forbidden' }, 403);
  }
  if (Number(body.amount) > Number(payment.amount)) {
    return j({ error: 'refund amount exceeds payment' }, 400);
  }
  // Paytm online refunds aren't wired yet — refuse rather than silently record
  // a "manual" refund (which would mark the invoice refunded without returning
  // money). Issue it from the Paytm dashboard until the refund API is built.
  if (payment.method === 'paytm') {
    return j({
      error:
        'Online Paytm refunds are not supported yet. Refund from your Paytm ' +
        'dashboard, then adjust the invoice manually.',
    }, 422);
  }

  const refundRow: Record<string, unknown> = {
    academy_id: payment.academy_id,
    payment_id: payment.id,
    amount: body.amount,
    reason: body.reason ?? null,
    approved_by: me.id,
    status: 'pending',
  };

  if (payment.method === 'razorpay' && payment.razorpay_payment_id) {
    try {
      // Refund through the same merchant account that captured the payment.
      const creds = await resolveRazorpayCreds(admin, payment.academy_id);
      const r = await refundRazorpayPayment({
        razorpay_payment_id: payment.razorpay_payment_id,
        amount_paise: Math.round(Number(body.amount) * 100),
      }, creds);
      refundRow.razorpay_refund_id = r.id;
      refundRow.status = r.status === 'processed' ? 'processed' : 'pending';
      refundRow.processed_at = r.status === 'processed'
        ? new Date().toISOString() : null;
    } catch (e) {
      return j({ error: (e as Error).message }, 502);
    }
  } else {
    // Manual refund — admin recorded it physically; mark processed now.
    refundRow.status = 'processed';
    refundRow.processed_at = new Date().toISOString();
  }

  // Mark the parent payment partially-refunded if amount < payment amount,
  // refunded if equal.
  const newPaymentStatus =
    Number(body.amount) >= Number(payment.amount) ? 'refunded'
      : 'partially_refunded';

  const { data: refund, error: rErr } = await admin
    .from('refunds').insert(refundRow).select().single();
  if (rErr) return j({ error: rErr.message }, 500);

  await admin.from('payments').update({ status: newPaymentStatus })
    .eq('id', payment.id);

  return j({ ok: true, refund });
});

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
