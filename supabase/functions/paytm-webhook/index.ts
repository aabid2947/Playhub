// Paytm callback / webhook. Set as the callbackUrl on initiateTransaction:
//   https://<project-ref>.supabase.co/functions/v1/paytm-webhook?academy=<academy_id>
//
// Security (invariant #6): we do NOT trust the posted body. We take only the
// ORDERID from it, then confirm the outcome against Paytm's Transaction-Status
// API (server-to-server, signed with the academy's own merchant key) and record
// only when that API reports TXN_SUCCESS and a matching payment_attempts row
// exists — so a forged callback can't fabricate a payment. Idempotent via
// payments.unique_event_id = 'paytm:<orderId>'. (The client also calls
// verify-paytm-payment; both go through the same confirmAndRecordPaytm helper.)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { confirmAndRecordPaytm } from '../_shared/paytm_record.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return j({ error: 'missing env' }, 500);

  const academyId = new URL(req.url).searchParams.get('academy');
  if (!academyId) return j({ error: 'academy param required' }, 400);

  const orderId = await extractOrderId(req);
  if (!orderId) return j({ ok: true, ignored: 'no ORDERID' });

  const admin = createClient(url, serviceKey);
  try {
    const result = await confirmAndRecordPaytm(admin, academyId, orderId);
    return j({ ok: true, status: result.status, order_id: orderId });
  } catch (e) {
    return j({ error: (e as Error).message }, 502);
  }
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
