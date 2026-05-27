// Cron daily ~02:00 IST: union of two sources →
//   - student_fee_assignments (per-student, overrides + one-offs)
//   - batch_fee_assignments × active enrollments (batch-wide fees)
//
// Generates one invoice per (student, fee_structure, period_start). The
// existing per-student dedupe check ensures a student covered by both
// sources gets a single invoice per period.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';
import {
  anchorPeriodStart,
  computeDiscounts,
  isoDate,
  nextPeriodStart,
  round2,
} from '../_shared/billing.ts';

interface Assignment {
  academy_id: string;
  student_id: string;
  fee_structure_id: string;
  start_date: string;
  end_date: string | null;
  billing_day: number | null;
  fee: {
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

  const studentLevel = await collectStudentLevel(admin);
  const batchLevel = await collectBatchLevel(admin);
  const all: Assignment[] = [...studentLevel, ...batchLevel];

  let scanned = all.length;
  let created = 0;
  for (const a of all) {
    if (a.fee.type === 'one_time') continue;
    if (a.end_date && new Date(a.end_date) < todayUtc) continue;

    const start = new Date(a.start_date + 'T00:00:00Z');
    const billingDay = a.billing_day ?? start.getUTCDate();

    const periodStart = anchorPeriodStart(todayUtc, a.fee.type, billingDay);
    if (todayUtc.getUTCDate() !== billingDay) continue;
    if (periodStart < start) continue;

    const periodEnd = nextPeriodStart(periodStart, a.fee.type);
    periodEnd.setUTCDate(periodEnd.getUTCDate() - 1);

    // Skip if invoice already exists for this (student, fee, period_start) —
    // dedupes across both assignment sources.
    const { count } = await admin
      .from('invoices')
      .select('id', { count: 'exact', head: true })
      .eq('student_id', a.student_id)
      .eq('fee_structure_id', a.fee_structure_id)
      .eq('period_start', isoDate(periodStart));
    if ((count ?? 0) > 0) continue;

    const taxAmount =
      round2(Number(a.fee.base_amount) * Number(a.fee.tax_pct) / 100);
    const dueDate = new Date(periodStart);
    dueDate.setUTCDate(dueDate.getUTCDate() + 7);

    const { data: number } = await admin
      .rpc('next_invoice_number', { p_academy_id: a.academy_id });
    if (!number) continue;

    const { data: invoice, error: iErr } = await admin
      .from('invoices')
      .insert({
        academy_id: a.academy_id,
        student_id: a.student_id,
        fee_structure_id: a.fee_structure_id,
        invoice_number: number,
        status: 'issued',
        period_start: isoDate(periodStart),
        period_end: isoDate(periodEnd),
        due_date: isoDate(dueDate),
        base_amount: a.fee.base_amount,
        tax_amount: taxAmount,
      })
      .select('id')
      .single();
    if (iErr || !invoice) continue;

    await admin.from('invoice_line_items').insert([
      {
        invoice_id: invoice.id,
        academy_id: a.academy_id,
        kind: 'base',
        description: a.fee.name,
        quantity: 1,
        unit_amount: a.fee.base_amount,
      },
      ...(taxAmount > 0
        ? [{
            invoice_id: invoice.id,
            academy_id: a.academy_id,
            kind: 'tax' as const,
            description: `Tax (${a.fee.tax_pct}%)`,
            quantity: 1,
            unit_amount: taxAmount,
          }]
        : []),
    ]);

    // Apply discounts (student-level + optional batch-level).
    await applyDiscounts(admin, {
      invoiceId: invoice.id,
      academyId: a.academy_id,
      studentId: a.student_id,
      baseAmount: Number(a.fee.base_amount),
      taxAmount,
      periodStart,
    });

    created++;
  }

  return j({
    ok: true,
    scanned,
    student_level: studentLevel.length,
    batch_level: batchLevel.length,
    created,
  });
});

interface DiscountStructure {
  id: string;
  name: string;
  type: 'percentage' | 'flat';
  value: number;
}

async function applyDiscounts(
  admin: ReturnType<typeof createClient>,
  args: {
    invoiceId: string;
    academyId: string;
    studentId: string;
    baseAmount: number;
    taxAmount: number;
    periodStart: Date;
  },
): Promise<void> {
  const periodStartStr = isoDate(args.periodStart);

  // Student-level: rows active for this period.
  const { data: studentRows } = await admin
    .from('student_discount_assignments')
    .select('discount_structure_id, stack_with_batch, start_date, end_date, '
        + 'discount:discount_structure_id(id, name, type, value)')
    .eq('student_id', args.studentId)
    .eq('is_active', true)
    .lte('start_date', periodStartStr);

  const studentActive = (studentRows ?? [])
    .filter((r: { end_date: string | null }) =>
      r.end_date === null || r.end_date >= periodStartStr,
    ) as unknown as Array<{
      stack_with_batch: boolean;
      discount: DiscountStructure | null;
    }>;

  const hasNonStacking = studentActive.some(
    (r) => r.stack_with_batch === false && r.discount !== null,
  );

  type Applied = { source: 'student' | 'batch'; discount: DiscountStructure };
  const applied: Applied[] = [];
  for (const r of studentActive) {
    if (r.discount) applied.push({ source: 'student', discount: r.discount });
  }

  if (!hasNonStacking) {
    // Batch-level: discounts attached to the student's active batches.
    const { data: enrolls } = await admin
      .from('batch_enrollments')
      .select('batch_id')
      .eq('student_id', args.studentId)
      .eq('enrollment_status', 'active');
    const batchIds = ((enrolls ?? []) as Array<{ batch_id: string }>)
      .map((e) => e.batch_id);
    if (batchIds.length > 0) {
      const { data: batchRows } = await admin
        .from('batch_discount_assignments')
        .select('discount_structure_id, start_date, end_date, '
            + 'discount:discount_structure_id(id, name, type, value)')
        .in('batch_id', batchIds)
        .eq('is_active', true)
        .lte('start_date', periodStartStr);
      const batchActive = (batchRows ?? []).filter(
        (r: { end_date: string | null }) =>
          r.end_date === null || r.end_date >= periodStartStr,
      ) as unknown as Array<{ discount: DiscountStructure | null }>;
      for (const r of batchActive) {
        if (r.discount) applied.push({ source: 'batch', discount: r.discount });
      }
    }
  }

  if (applied.length === 0) return;

  // Compute each discount's amount, clamping the running total at base+tax.
  const { used, lines } = computeDiscounts(applied, args.baseAmount, args.taxAmount);

  if (used > 0) {
    await admin.from('invoices').update({ discount_amount: used })
      .eq('id', args.invoiceId);
    await admin.from('invoice_line_items').insert(
      lines.map((l) => ({
        invoice_id: args.invoiceId,
        academy_id: args.academyId,
        kind: 'discount',
        description: l.description,
        quantity: 1,
        unit_amount: -l.amount,
      })),
    );
  }
}

async function collectStudentLevel(
  admin: ReturnType<typeof createClient>,
): Promise<Assignment[]> {
  const { data } = await admin
    .from('student_fee_assignments')
    .select('academy_id, student_id, fee_structure_id, start_date, '
        + 'end_date, billing_day, '
        + 'fee:fee_structure_id(type, base_amount, tax_pct, name)')
    .eq('is_active', true);
  return ((data ?? []) as unknown as Assignment[])
    .filter((r) => r.fee !== null);
}

async function collectBatchLevel(
  admin: ReturnType<typeof createClient>,
): Promise<Assignment[]> {
  // Batch-level fee assignments + active enrollments → expand to per-student
  // pseudo-assignments that share the per-student code path.
  const { data: bfas } = await admin
    .from('batch_fee_assignments')
    .select('academy_id, batch_id, fee_structure_id, start_date, '
        + 'end_date, billing_day, '
        + 'fee:fee_structure_id(type, base_amount, tax_pct, name)')
    .eq('is_active', true);

  const out: Assignment[] = [];
  for (const bfa of (bfas ?? []) as unknown as Array<{
    academy_id: string;
    batch_id: string;
    fee_structure_id: string;
    start_date: string;
    end_date: string | null;
    billing_day: number | null;
    fee: Assignment['fee'] | null;
  }>) {
    if (!bfa.fee) continue;
    const { data: enrolls } = await admin
      .from('batch_enrollments')
      .select('student_id')
      .eq('batch_id', bfa.batch_id)
      .eq('enrollment_status', 'active');
    for (const e of (enrolls ?? []) as Array<{ student_id: string }>) {
      out.push({
        academy_id: bfa.academy_id,
        student_id: e.student_id,
        fee_structure_id: bfa.fee_structure_id,
        start_date: bfa.start_date,
        end_date: bfa.end_date,
        billing_day: bfa.billing_day,
        fee: bfa.fee,
      });
    }
  }
  return out;
}

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
