// Client-called right after the SaaS Razorpay sheet closes:
//   { saas_invoice_id, razorpay_order_id, razorpay_payment_id }
// Confirms the payment with Razorpay (PLATFORM keys — SaaS billing) and records
// it into saas_payments if captured, so the academy activates without waiting
// for the async platform webhook (which may not be configured). This is the
// SaaS counterpart of verify-razorpay-payment (the fee-collection verify).
//
// Authorisation: the caller must be able to read the SaaS invoice under their
// JWT (owner/admin of that academy) — otherwise 403. Recording runs through the
// same idempotent path the webhook converges on (unique razorpay_payment_id).
//
// Deploy with JWT verification ON (caller-authorised) — the default.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { confirmAndRecordSaasRazorpay } from '../_shared/saas_razorpay_record.ts';

interface Body {
  saas_invoice_id: string;
  razorpay_order_id: string;
  razorpay_payment_id: string;
}

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
  if (
    !body?.saas_invoice_id || !body?.razorpay_order_id ||
    !body?.razorpay_payment_id
  ) {
    return j({
      error:
        'saas_invoice_id + razorpay_order_id + razorpay_payment_id required',
    }, 400);
  }

  const admin = createClient(url, serviceKey);

  // Resolve the SaaS invoice → academy (service role).
  const { data: inv } = await admin
    .from('saas_invoices')
    .select('id, academy_id')
    .eq('id', body.saas_invoice_id)
    .maybeSingle();
  if (!inv) return j({ error: 'invoice not found' }, 404);

  // Authorise: the caller must be able to read that SaaS invoice under their JWT.
  const caller = createClient(url, anonKey, {
    global: { headers: { authorization: auth } },
  });
  const { data: visible } = await caller
    .from('saas_invoices')
    .select('id')
    .eq('id', body.saas_invoice_id)
    .maybeSingle();
  if (!visible) return j({ error: 'forbidden' }, 403);

  try {
    const result = await confirmAndRecordSaasRazorpay(
      admin,
      inv.academy_id as string,
      body.saas_invoice_id,
      body.razorpay_order_id,
      body.razorpay_payment_id,
    );
    return j({ status: result.status, recorded: result.recorded });
  } catch (e) {
    return j({ error: (e as Error).message }, 502);
  }
});

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
