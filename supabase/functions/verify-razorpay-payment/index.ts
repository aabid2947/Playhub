// Client-called right after the Razorpay sheet closes:
//   { razorpay_order_id, razorpay_payment_id }
// Confirms the payment with Razorpay (authoritative) and records it if captured,
// returning the status so the app shows an accurate result without waiting for
// the async webhook. Authorisation: the caller must be able to see the
// underlying invoice (RLS) — otherwise 403. Recording runs through the same
// idempotent path the webhook converges on (unique razorpay_payment_id).
//
// Deploy with JWT verification ON (caller-authorised) — the default.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { confirmAndRecordRazorpay } from '../_shared/razorpay_record.ts';

interface Body {
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
  if (!body?.razorpay_order_id || !body?.razorpay_payment_id) {
    return j({ error: 'razorpay_order_id + razorpay_payment_id required' }, 400);
  }

  const admin = createClient(url, serviceKey);

  // Resolve the attempt → invoice/academy (service role; attempts have no app
  // read policy).
  const { data: attempt } = await admin
    .from('payment_attempts')
    .select('invoice_id, academy_id')
    .eq('razorpay_order_id', body.razorpay_order_id)
    .maybeSingle();
  if (!attempt) return j({ error: 'order not found' }, 404);

  // Authorise: the caller must be able to read that invoice under their JWT.
  const caller = createClient(url, anonKey, {
    global: { headers: { authorization: auth } },
  });
  const { data: visible } = await caller
    .from('invoices')
    .select('id')
    .eq('id', attempt.invoice_id)
    .maybeSingle();
  if (!visible) return j({ error: 'forbidden' }, 403);

  try {
    const result = await confirmAndRecordRazorpay(
      admin,
      attempt.academy_id,
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
