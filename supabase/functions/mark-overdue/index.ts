// Cron daily ~01:00 IST: scans unpaid invoices past due_date + grace_days,
// applies the academy's late-fee policy, flips status → 'overdue', adds
// a 'late_fee' line item if not yet present.
//
// Late-fee policy (set on academies, can be overridden per fee_structure):
//   - 'none'      → no fee applied
//   - 'one_time'  → fee added once when first overdue
//   - 'daily'     → fee added per day past grace; late_fee_amount keeps
//                   accruing until the invoice is paid

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';

interface Invoice {
  id: string;
  academy_id: string;
  fee_structure_id: string | null;
  status: string;
  due_date: string;
  base_amount: number;
  amount: number;
  late_fee_amount: number;
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

  const { data: invoices } = await admin
    .from('invoices')
    .select('id, academy_id, fee_structure_id, status, due_date, '
        + 'base_amount, amount, late_fee_amount')
    .in('status', ['issued', 'partial', 'overdue']);

  let updated = 0;
  let feeRows = 0;

  for (const inv of (invoices ?? []) as Invoice[]) {
    const due = new Date(inv.due_date + 'T00:00:00Z');
    const today = new Date();

    // Resolve effective policy: fee_structure overrides academy.
    const policy = await resolvePolicy(admin, inv);
    if (!policy) continue;

    const graceUntil = new Date(due);
    graceUntil.setUTCDate(graceUntil.getUTCDate() + policy.grace_days);
    if (today < graceUntil) continue; // still in grace

    if (policy.policy === 'none') {
      if (inv.status !== 'overdue') {
        await admin.from('invoices').update({ status: 'overdue' })
          .eq('id', inv.id);
        updated++;
      }
      continue;
    }

    // Compute the fee owed *up to today*. flat takes precedence; pct
    // applied to base_amount.
    const daysLate = Math.max(
      1,
      Math.floor((today.getTime() - graceUntil.getTime()) / 86400_000) + 1,
    );
    const periods = policy.policy === 'daily' ? daysLate : 1;
    const perPeriod = policy.flat ?? (policy.pct
      ? round2(Number(inv.base_amount) * policy.pct / 100)
      : 0);
    const targetFee = round2(perPeriod * periods);
    const delta = round2(targetFee - Number(inv.late_fee_amount));

    if (delta > 0) {
      await admin.from('invoices').update({
        late_fee_amount: targetFee,
        status: 'overdue',
      }).eq('id', inv.id);
      await admin.from('invoice_line_items').insert({
        invoice_id: inv.id,
        academy_id: inv.academy_id,
        kind: 'late_fee',
        description: policy.policy === 'daily'
          ? `Late fee (${periods}d × ₹${perPeriod})`
          : `Late fee`,
        quantity: 1,
        unit_amount: delta,
      });
      updated++;
      feeRows++;
    } else if (inv.status !== 'overdue') {
      await admin.from('invoices').update({ status: 'overdue' })
        .eq('id', inv.id);
      updated++;
    }
  }

  return j({ ok: true, scanned: (invoices ?? []).length, updated, fee_rows: feeRows });
});

interface ResolvedPolicy {
  policy: 'none' | 'one_time' | 'daily';
  grace_days: number;
  pct: number | null;
  flat: number | null;
}

async function resolvePolicy(
  admin: ReturnType<typeof createClient>,
  inv: Invoice,
): Promise<ResolvedPolicy | null> {
  // Pull fee_structure overrides first
  let fs: {
    late_fee_pct: number | null;
    late_fee_flat: number | null;
    late_fee_grace_days: number | null;
    late_fee_policy: string | null;
  } | null = null;
  if (inv.fee_structure_id) {
    const { data } = await admin
      .from('fee_structures')
      .select('late_fee_pct, late_fee_flat, late_fee_grace_days, late_fee_policy')
      .eq('id', inv.fee_structure_id)
      .single();
    fs = data;
  }
  const { data: ac } = await admin
    .from('academies')
    .select('late_fee_grace_days, late_fee_policy')
    .eq('id', inv.academy_id)
    .single();
  if (!ac) return null;

  return {
    policy: (fs?.late_fee_policy ?? ac.late_fee_policy) as
      'none' | 'one_time' | 'daily',
    grace_days: fs?.late_fee_grace_days ?? ac.late_fee_grace_days ?? 5,
    pct: fs?.late_fee_pct,
    flat: fs?.late_fee_flat,
  };
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
