// Admin/parent endpoint: takes { invoice_id }, creates a Razorpay order
// for the unpaid balance, records a payment_attempts row, returns
// { order_id, key_id, amount_paise, currency } so the client SDK can open
// the checkout sheet.
//
// PLAN.md decision: 3× auto-retry on failure. We refuse to create a 4th
// attempt for the same invoice and return 409.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { createRazorpayOrder } from '../_shared/razorpay.ts';
import { resolveRazorpayCreds } from '../_shared/payment_gateway.ts';
import { toPaise } from '../_shared/billing.ts';

interface Body { invoice_id: string }

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
  if (!body?.invoice_id) return j({ error: 'invoice_id required' }, 400);

  // Caller-scoped client: RLS enforces that the user can only create
  // orders against invoices in their own academy.
  const caller = createClient(url, anonKey, {
    global: { headers: { authorization: auth } },
  });
  const { data: invoice, error: invErr } = await caller
    .from('invoices')
    .select('id, academy_id, student_id, invoice_number, amount, amount_paid, status')
    .eq('id', body.invoice_id)
    .single();
  if (invErr || !invoice) return j({ error: 'invoice not found' }, 404);
  if (invoice.status === 'paid' || invoice.status === 'cancelled') {
    return j({ error: `invoice is ${invoice.status}` }, 409);
  }

  const balance = Number(invoice.amount) - Number(invoice.amount_paid);
  if (balance <= 0) return j({ error: 'invoice already settled' }, 409);

  // Service-role client for attempts (RLS blocks direct attempts inserts).
  const admin = createClient(url, serviceKey);

  const { count } = await admin
    .from('payment_attempts')
    .select('id', { count: 'exact', head: true })
    .eq('invoice_id', invoice.id);
  const attemptNumber = (count ?? 0) + 1;
  if (attemptNumber > 3) {
    return j({ error: 'max 3 attempts reached for this invoice' }, 409);
  }

  // Use the academy's own Razorpay merchant keys when configured + enabled;
  // otherwise fall back to the platform-wide keys. Secrets stay server-side.
  let creds: Awaited<ReturnType<typeof resolveRazorpayCreds>>;
  try {
    creds = await resolveRazorpayCreds(admin, invoice.academy_id);
  } catch (e) {
    return j({ error: (e as Error).message }, 500);
  }

  let order: Awaited<ReturnType<typeof createRazorpayOrder>>;
  try {
    order = await createRazorpayOrder({
      amount_paise: toPaise(balance),
      currency: 'INR',
      receipt: invoice.invoice_number,
      notes: {
        invoice_id: invoice.id,
        academy_id: invoice.academy_id,
        student_id: invoice.student_id,
        attempt: String(attemptNumber),
      },
    }, creds);
  } catch (e) {
    return j({ error: (e as Error).message }, 502);
  }

  const { error: aErr } = await admin.from('payment_attempts').insert({
    academy_id: invoice.academy_id,
    invoice_id: invoice.id,
    attempt_number: attemptNumber,
    razorpay_order_id: order.id,
    amount: balance,
    status: 'created',
  });
  if (aErr) return j({ error: aErr.message }, 500);

  return j({
    order_id: order.id,
    key_id: creds.keyId,
    amount_paise: order.amount,
    currency: order.currency,
    invoice_number: invoice.invoice_number,
    attempt_number: attemptNumber,
  });
});

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
