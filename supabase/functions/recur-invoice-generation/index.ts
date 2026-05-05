// Cron daily ~02:00 IST: for every active student_fee_assignment whose
// fee_structure.type is recurring (monthly/quarterly/annual), generate
// the next invoice if today is the billing day and an invoice for the
// current period doesn't already exist.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';

interface SfaRow {
  id: string;
  academy_id: string;
  student_id: string;
  fee_structure_id: string;
  start_date: string;
  end_date: string | null;
  billing_day: number | null;
  fee_structures: {
    type: 'monthly' | 'quarterly' | 'annual' | 'one_time';
    base_amount: number;
    tax_pct: number;
    name: string;
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

  const { data: assignments, error } = await admin
    .from('student_fee_assignments')
    .select('id, academy_id, student_id, fee_structure_id, start_date, '
        + 'end_date, billing_day, '
        + 'fee_structures:fee_structure_id(type, base_amount, tax_pct, name)')
    .eq('is_active', true);
  if (error) return j({ error: error.message }, 500);

  let created = 0;
  for (const sfa of (assignments ?? []) as unknown as SfaRow[]) {
    const fs = sfa.fee_structures;
    if (!fs || fs.type === 'one_time') continue;
    if (sfa.end_date && new Date(sfa.end_date) < todayUtc) continue;

    const start = new Date(sfa.start_date + 'T00:00:00Z');
    const billingDay = sfa.billing_day ?? start.getUTCDate();

    // Compute current period start/end from frequency.
    const periodStart = anchorPeriodStart(todayUtc, fs.type, billingDay);
    if (todayUtc.getUTCDate() !== billingDay) continue;
    if (periodStart < start) continue;

    const periodEnd = nextPeriodStart(periodStart, fs.type);
    periodEnd.setUTCDate(periodEnd.getUTCDate() - 1);

    // Skip if already issued for this period.
    const { count } = await admin
      .from('invoices')
      .select('id', { count: 'exact', head: true })
      .eq('student_id', sfa.student_id)
      .eq('fee_structure_id', sfa.fee_structure_id)
      .eq('period_start', isoDate(periodStart));
    if ((count ?? 0) > 0) continue;

    const taxAmount = round2(Number(fs.base_amount) * Number(fs.tax_pct) / 100);
    const dueDate = new Date(periodStart);
    dueDate.setUTCDate(dueDate.getUTCDate() + 7); // default 7-day window

    const { data: number } = await admin
      .rpc('next_invoice_number', { p_academy_id: sfa.academy_id });
    if (!number) continue;

    const { data: invoice, error: iErr } = await admin
      .from('invoices')
      .insert({
        academy_id: sfa.academy_id,
        student_id: sfa.student_id,
        fee_structure_id: sfa.fee_structure_id,
        invoice_number: number,
        status: 'issued',
        period_start: isoDate(periodStart),
        period_end: isoDate(periodEnd),
        due_date: isoDate(dueDate),
        base_amount: fs.base_amount,
        tax_amount: taxAmount,
      })
      .select('id')
      .single();
    if (iErr || !invoice) continue;

    await admin.from('invoice_line_items').insert([
      {
        invoice_id: invoice.id,
        academy_id: sfa.academy_id,
        kind: 'base',
        description: fs.name,
        quantity: 1,
        unit_amount: fs.base_amount,
      },
      ...(taxAmount > 0
        ? [{
            invoice_id: invoice.id,
            academy_id: sfa.academy_id,
            kind: 'tax' as const,
            description: `Tax (${fs.tax_pct}%)`,
            quantity: 1,
            unit_amount: taxAmount,
          }]
        : []),
    ]);
    created++;
  }

  return j({ ok: true, scanned: (assignments ?? []).length, created });
});

function anchorPeriodStart(
  today: Date,
  type: 'monthly' | 'quarterly' | 'annual' | 'one_time',
  billingDay: number,
): Date {
  const d = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), billingDay));
  if (type === 'monthly') return d;
  if (type === 'quarterly') {
    const q = Math.floor(today.getUTCMonth() / 3) * 3;
    return new Date(Date.UTC(today.getUTCFullYear(), q, billingDay));
  }
  // annual
  return new Date(Date.UTC(today.getUTCFullYear(), 0, billingDay));
}

function nextPeriodStart(
  start: Date,
  type: 'monthly' | 'quarterly' | 'annual' | 'one_time',
): Date {
  const d = new Date(start);
  if (type === 'monthly') d.setUTCMonth(d.getUTCMonth() + 1);
  else if (type === 'quarterly') d.setUTCMonth(d.getUTCMonth() + 3);
  else d.setUTCFullYear(d.getUTCFullYear() + 1);
  return d;
}

function isoDate(d: Date): string {
  return d.toISOString().substring(0, 10);
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
