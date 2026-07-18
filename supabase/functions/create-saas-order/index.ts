// Owner self-serve SaaS checkout — creates (or reuses) a SaaS invoice for the
// caller's academy and a Razorpay order to pay it. PlayHub bills the academy, so
// this ALWAYS charges through the PLATFORM Razorpay keys (never the academy's own
// merchant gateway, which is for parents paying the academy).
//
// Body: { plan_code?: string }   // defaults to 'starter' (the ₹100 self-serve plan)
//
// Flow:
//   1. Authenticate caller; must be academy_owner/academy_admin with an academy.
//   2. Point the subscription at the chosen plan (status stays 'trial' until the
//      payment clears — the webhook + reactivate trigger flip it to 'active').
//   3. Reuse an existing unpaid SaaS invoice for this subscription, else issue one
//      for the plan's monthly_price.
//   4. Create a Razorpay order tagged notes.invoice_type='saas' so the platform
//      razorpay-webhook records it into saas_payments.
//
// Returns: { provider:'razorpay', order_id, key_id, amount_paise, currency,
//            invoice_number }
//
// Deploy with JWT verification ON (caller-authorised) — the default.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { createRazorpayOrder, platformRazorpayCreds } from '../_shared/razorpay.ts';

interface Body {
  plan_code?: string;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const auth = req.headers.get('authorization') ?? '';
  if (!auth.toLowerCase().startsWith('bearer ')) {
    return j({ error: 'unauthorised' }, 401);
  }
  const token = auth.slice(7);

  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anon || !key) return j({ error: 'missing env' }, 500);

  const body = (await req.json().catch(() => ({}))) as Body;
  const planCode = (body.plan_code ?? 'starter').trim();

  // Verify the caller and read their profile under RLS.
  const verifier = createClient(url, anon);
  const { data: ures, error: uerr } = await verifier.auth.getUser(token);
  if (uerr || !ures.user) return j({ error: 'unauthorised' }, 401);

  const callerClient = createClient(url, anon, {
    global: { headers: { authorization: `Bearer ${token}` } },
  });
  const { data: caller, error: cerr } = await callerClient.from('users')
    .select('id, role, academy_id').eq('id', ures.user.id).single();
  if (cerr || !caller?.academy_id) {
    return j({ error: 'no academy', detail: cerr?.message ?? 'no users row' }, 403);
  }
  if (!['academy_owner', 'academy_admin'].includes(caller.role as string)) {
    return j({ error: 'only an owner or admin can start a subscription' }, 403);
  }
  const academyId = caller.academy_id as string;

  const admin = createClient(url, key);

  // Resolve the plan + the academy's subscription + name.
  const { data: plan, error: planErr } = await admin.from('subscription_plans')
    .select('id, monthly_price, name').eq('code', planCode).maybeSingle();
  if (planErr || !plan) return j({ error: `plan ${planCode} not found` }, 400);

  const { data: sub, error: subErr } = await admin.from('academy_subscriptions')
    .select('id, status').eq('academy_id', academyId).maybeSingle();
  if (subErr || !sub) return j({ error: 'no subscription for academy' }, 400);

  const { data: academy } = await admin.from('academies')
    .select('name').eq('id', academyId).maybeSingle();
  const academyName = (academy?.name as string | undefined) ?? 'Academy';

  const amount = Number(plan.monthly_price);
  if (!Number.isFinite(amount) || amount <= 0) {
    return j({ error: 'plan has no valid price' }, 400);
  }

  // Point the subscription at the chosen plan (monthly). Status stays as-is —
  // the payment is what activates it (reactivate_paid_subscription trigger).
  await admin.from('academy_subscriptions')
    .update({ plan_id: plan.id, billing_cycle: 'monthly' })
    .eq('id', sub.id);

  // Reuse an existing unpaid invoice for this subscription, else issue one.
  let invoiceId: string;
  let invoiceNumber: string;
  let invoiceAmount: number;

  const { data: openInv } = await admin.from('saas_invoices')
    .select('id, invoice_number, total_amount')
    .eq('subscription_id', sub.id)
    .in('status', ['issued', 'past_due'])
    .order('issued_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (openInv) {
    invoiceId = openInv.id as string;
    invoiceNumber = openInv.invoice_number as string;
    invoiceAmount = Number(openInv.total_amount);
  } else {
    const now = new Date();
    const ym = `${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
    invoiceNumber = `SAAS-${ym}-${academyId.slice(0, 8)}-${now.getTime().toString(36)}`;
    const periodEnd = new Date(now);
    periodEnd.setUTCMonth(periodEnd.getUTCMonth() + 1);
    const dueDate = new Date(now);
    dueDate.setUTCDate(dueDate.getUTCDate() + 7);

    const { data: created, error: invErr } = await admin.from('saas_invoices')
      .insert({
        academy_id: academyId,
        subscription_id: sub.id,
        invoice_number: invoiceNumber,
        status: 'issued',
        period_start: now.toISOString(),
        period_end: periodEnd.toISOString(),
        due_date: dueDate.toISOString().slice(0, 10),
        amount,
        currency: 'INR',
      })
      .select('id, total_amount')
      .single();
    if (invErr || !created) {
      return j({ error: `could not create invoice: ${invErr?.message}` }, 500);
    }
    invoiceId = created.id as string;
    invoiceAmount = Number(created.total_amount);
  }

  const amountPaise = Math.round(invoiceAmount * 100);

  // Platform keys only — PlayHub is the merchant for SaaS billing.
  let creds;
  try {
    creds = platformRazorpayCreds();
  } catch (e) {
    return j({ error: (e as Error).message }, 500);
  }

  let order;
  try {
    order = await createRazorpayOrder({
      amount_paise: amountPaise,
      currency: 'INR',
      receipt: invoiceNumber,
      notes: {
        invoice_type: 'saas',
        invoice_id: invoiceId,
        academy_id: academyId,
        subscription_id: sub.id,
      },
    }, creds);
  } catch (e) {
    return j({ error: `could not create order: ${(e as Error).message}` }, 502);
  }

  return j({
    provider: 'razorpay',
    order_id: order.id,
    key_id: creds.keyId,
    amount_paise: amountPaise,
    currency: 'INR',
    invoice_number: invoiceNumber,
    // invoice_id lets the client call verify-saas-payment after the sheet
    // closes (verify-on-return), so a captured charge activates the academy
    // even if the async platform webhook never fires.
    invoice_id: invoiceId,
    academy_name: academyName,
  });
});

function j(b: unknown, status = 200) {
  return new Response(JSON.stringify(b), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
