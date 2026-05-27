// Cron daily ~02:30 IST: for every academy_subscription whose
// current_period_end is on or before today, issues a saas_invoice for the
// next period and rolls the period window forward.
//
// Trial subscriptions are not billed until they convert to active. We do
// NOT auto-charge — the academy owner pays via the Razorpay-flutter sheet
// triggered from the subscription mgmt page; auto-debit lands later via
// Razorpay subscriptions integration.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';
import { nextPeriodEnd } from '../_shared/billing.ts';

interface Sub {
  id: string;
  academy_id: string;
  plan_id: string;
  status: string;
  billing_cycle: 'monthly' | 'yearly';
  current_period_start: string;
  current_period_end: string;
  trial_ends_at: string | null;
  plan: {
    monthly_price: number;
    yearly_price: number | null;
    currency: string;
  };
}

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
  const todayUtc = new Date(Date.UTC(
    today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate(),
  ));
  const todayIso = todayUtc.toISOString();

  // Pull due subscriptions. We don't bill 'trial' (until converted) or
  // 'cancelled'/'suspended'. 'past_due' rebills — they owe more.
  const { data: subs } = await admin
    .from('academy_subscriptions')
    .select(
      'id, academy_id, plan_id, status, billing_cycle, '
      + 'current_period_start, current_period_end, trial_ends_at, '
      + 'plan:plan_id(monthly_price, yearly_price, currency)',
    )
    .lte('current_period_end', todayIso)
    .in('status', ['active', 'past_due']);

  const list = (subs ?? []) as unknown as Sub[];
  let created = 0;

  for (const s of list) {
    if (!s.plan) continue;
    const periodStart = new Date(s.current_period_end);
    const periodEnd = nextPeriodEnd(periodStart, s.billing_cycle);

    const amount = s.billing_cycle === 'yearly'
      ? Number(s.plan.yearly_price ?? 0)
      : Number(s.plan.monthly_price);
    if (amount <= 0) continue;

    // Dedupe: skip if a saas_invoice for this period_start already exists.
    const { count } = await admin
      .from('saas_invoices')
      .select('id', { count: 'exact', head: true })
      .eq('subscription_id', s.id)
      .eq('period_start', periodStart.toISOString());
    if ((count ?? 0) > 0) {
      // Still roll the period forward to avoid scanning forever.
      await admin.from('academy_subscriptions')
        .update({
          current_period_start: periodStart.toISOString(),
          current_period_end: periodEnd.toISOString(),
        })
        .eq('id', s.id);
      continue;
    }

    const dueDate = new Date(periodStart);
    dueDate.setUTCDate(dueDate.getUTCDate() + 7);

    const invoiceNumber = `SAAS-${todayUtc.getUTCFullYear()}${
      String(todayUtc.getUTCMonth() + 1).padStart(2, '0')
    }-${s.academy_id.substring(0, 8)}-${Date.now().toString(36)}`;

    const { error: iErr } = await admin
      .from('saas_invoices')
      .insert({
        academy_id: s.academy_id,
        subscription_id: s.id,
        invoice_number: invoiceNumber,
        status: 'issued',
        period_start: periodStart.toISOString(),
        period_end: periodEnd.toISOString(),
        due_date: dueDate.toISOString().substring(0, 10),
        amount,
        tax_amount: 0,
        currency: s.plan.currency,
      });
    if (iErr) continue;

    await admin
      .from('academy_subscriptions')
      .update({
        status: 'past_due', // remains past_due until paid
        current_period_start: periodStart.toISOString(),
        current_period_end: periodEnd.toISOString(),
      })
      .eq('id', s.id);

    created++;
  }

  return j({ ok: true, scanned: list.length, created });
});

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
