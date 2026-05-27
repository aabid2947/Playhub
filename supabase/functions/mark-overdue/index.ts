// Cron daily ~01:00 IST: scans unpaid invoices past due_date + grace_days,
// applies the fee_structure's late-fee policy, flips status → 'overdue',
// adds a 'late_fee' line item if not yet present.
//
// Late-fee config is now single-source-of-truth on fee_structures.
// Manual ad-hoc invoices with no fee_structure_id only get the status
// flip — no fee is assessed.
//
// Policy values:
//   - 'none'      → no fee applied
//   - 'one_time'  → fee added once when first overdue
//   - 'daily'     → fee added per day past grace; late_fee_amount keeps
//                   accruing until the invoice is paid

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';
import { computeLateFee, daysLateSinceGrace } from '../_shared/billing.ts';

interface InvoiceWithFee {
  id: string;
  academy_id: string;
  fee_structure_id: string | null;
  status: string;
  due_date: string;
  base_amount: number;
  amount: number;
  late_fee_amount: number;
  fee_structures: {
    late_fee_policy: 'none' | 'one_time' | 'daily';
    late_fee_grace_days: number;
    late_fee_pct: number | null;
    late_fee_flat: number | null;
  } | null;
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
    .select(
      'id, academy_id, fee_structure_id, status, due_date, '
      + 'base_amount, amount, late_fee_amount, '
      + 'fee_structures:fee_structure_id('
      + 'late_fee_policy, late_fee_grace_days, late_fee_pct, late_fee_flat)',
    )
    .in('status', ['issued', 'partial', 'overdue']);

  let updated = 0;
  let feeRows = 0;

  for (const inv of (invoices ?? []) as unknown as InvoiceWithFee[]) {
    const fs = inv.fee_structures;
    // Manual invoices (no fee_structure_id) just get the status flip.
    if (!fs) {
      const due = new Date(inv.due_date + 'T00:00:00Z');
      if (new Date() >= due && inv.status !== 'overdue') {
        await admin.from('invoices').update({ status: 'overdue' })
          .eq('id', inv.id);
        updated++;
      }
      continue;
    }

    const due = new Date(inv.due_date + 'T00:00:00Z');
    const today = new Date();
    const graceUntil = new Date(due);
    graceUntil.setUTCDate(graceUntil.getUTCDate() + fs.late_fee_grace_days);
    if (today < graceUntil) continue; // still in grace

    if (fs.late_fee_policy === 'none') {
      if (inv.status !== 'overdue') {
        await admin.from('invoices').update({ status: 'overdue' })
          .eq('id', inv.id);
        updated++;
      }
      continue;
    }

    // Compute fee owed up to today. flat takes precedence; else pct of base.
    const daysLate = daysLateSinceGrace(graceUntil, today);
    const { perPeriod, periods, targetFee, delta } = computeLateFee({
      policy: fs.late_fee_policy,
      baseAmount: Number(inv.base_amount),
      lateFeePct: fs.late_fee_pct,
      lateFeeFlat: fs.late_fee_flat,
      daysLate,
      alreadyCharged: Number(inv.late_fee_amount),
    });

    if (delta > 0) {
      await admin.from('invoices').update({
        late_fee_amount: targetFee,
        status: 'overdue',
      }).eq('id', inv.id);
      await admin.from('invoice_line_items').insert({
        invoice_id: inv.id,
        academy_id: inv.academy_id,
        kind: 'late_fee',
        description: fs.late_fee_policy === 'daily'
          ? `Late fee (${periods}d × ₹${perPeriod})`
          : 'Late fee',
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

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
