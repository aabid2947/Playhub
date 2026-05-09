// Cron daily ~03:30 IST: walks past-due saas_invoices.
//   - 7+ days past due  → flag invoice as 'past_due', subscription stays
//                          past_due (still has read access, no charge yet)
//   - 14+ days past due → suspend the academy_subscription + flip
//                          academies.subscription_status to 'suspended'
//                          + academies.is_active = false. Owner sees a
//                          grace-period banner asking to pay or contact
//                          support.
// Idempotent: re-running doesn't double-suspend.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';

const SOFT_GRACE_DAYS = 7;
const HARD_GRACE_DAYS = 14;

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const denied = authoriseCron(req);
  if (denied) return denied;

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return j({ error: 'missing env' }, 500);
  const admin = createClient(url, key);

  const today = new Date();
  const today0 = new Date(Date.UTC(
    today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate(),
  ));
  const softThreshold = new Date(today0);
  softThreshold.setUTCDate(softThreshold.getUTCDate() - SOFT_GRACE_DAYS);
  const hardThreshold = new Date(today0);
  hardThreshold.setUTCDate(hardThreshold.getUTCDate() - HARD_GRACE_DAYS);

  // Step 1: flag past-due invoices that have crossed the soft grace.
  const { data: dueInvoices } = await admin
    .from('saas_invoices')
    .select('id, academy_id, subscription_id, due_date, status')
    .eq('status', 'issued')
    .lte('due_date', softThreshold.toISOString().substring(0, 10));

  let flaggedCount = 0;
  for (const inv of (dueInvoices ?? []) as Array<{ id: string }>) {
    const { error } = await admin
      .from('saas_invoices')
      .update({ status: 'past_due' })
      .eq('id', inv.id);
    if (!error) flaggedCount++;
  }

  // Step 2: find subscriptions with at least one invoice past hard grace
  // and suspend them. Distinct academy_ids only.
  const { data: hardOverdue } = await admin
    .from('saas_invoices')
    .select('academy_id, subscription_id')
    .in('status', ['issued', 'past_due'])
    .lte('due_date', hardThreshold.toISOString().substring(0, 10));

  const seen = new Set<string>();
  let suspendedCount = 0;
  for (const inv of (hardOverdue ?? []) as Array<{ academy_id: string; subscription_id: string }>) {
    if (seen.has(inv.subscription_id)) continue;
    seen.add(inv.subscription_id);

    await admin
      .from('academy_subscriptions')
      .update({ status: 'suspended' })
      .eq('id', inv.subscription_id)
      .neq('status', 'suspended');

    await admin
      .from('academies')
      .update({ subscription_status: 'suspended', is_active: false })
      .eq('id', inv.academy_id)
      .neq('subscription_status', 'suspended');

    suspendedCount++;
  }

  return j({
    ok: true,
    flagged_past_due: flaggedCount,
    suspended: suspendedCount,
  });
});

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
