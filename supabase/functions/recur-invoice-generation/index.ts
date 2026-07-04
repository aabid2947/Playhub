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
  currentPeriodStart,
  isoDate,
  nextPeriodStart,
  round2,
  weeklyPeriodStart,
} from '../_shared/billing.ts';

interface Assignment {
  academy_id: string;
  student_id: string;
  fee_structure_id: string;
  start_date: string;
  end_date: string | null;
  billing_day: number | null;
  fee: {
    type: 'weekly' | 'monthly' | 'quarterly' | 'annual' | 'one_time';
    base_amount: number;
    tax_pct: number;
    name: string;
  };
}

/** Optional scope for an ad-hoc (app-triggered) run; all empty = full cron. */
interface Filter {
  studentId?: string;
  batchId?: string;
  academyId?: string;
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

  // Optional scope. The scheduled cron sends no body → full run across every
  // academy. The app sends `{ academy_id, student_id }` or `{ academy_id,
  // batch_id }` right after assigning a fee, to materialise just that scope's
  // current-period invoice immediately (no 24h wait). Same idempotent dedupe,
  // so eager + scheduled runs can never double-bill.
  const filter: Filter = {};
  try {
    const body = await req.json();
    if (body && typeof body === 'object') {
      if (typeof body.student_id === 'string') filter.studentId = body.student_id;
      if (typeof body.batch_id === 'string') filter.batchId = body.batch_id;
      if (typeof body.academy_id === 'string') filter.academyId = body.academy_id;
    }
  } catch (_) {
    // No / non-JSON body → unscoped full run (the scheduled cron).
  }
  // A scoped run is the app's eager call right after assigning a fee / enrolling
  // a student. It materialises the CURRENT period immediately (no day-of-month
  // gate); the unscoped scheduled cron keeps the gate so it only issues on the
  // billing day. Dedupe makes the two safe to overlap.
  const scoped = !!(filter.studentId || filter.batchId);

  const today = new Date();
  const todayUtc = new Date(Date.UTC(
    today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate(),
  ));

  const studentLevel = await collectStudentLevel(admin, filter);
  const batchLevel = await collectBatchLevel(admin, filter);
  const all: Assignment[] = [...studentLevel, ...batchLevel];

  let scanned = all.length;
  let created = 0;
  for (const a of all) {
    if (a.end_date && new Date(a.end_date) < todayUtc) continue;

    const start = new Date(a.start_date + 'T00:00:00Z');
    // An assignment that hasn't begun yet bills nothing.
    if (todayUtc < start) continue;

    // Resolve the [periodStart, periodEnd] this run should try to invoice.
    // Each fee type anchors its period differently:
    //   one_time → a single charge dated on the assignment start_date
    //   weekly   → rolling 7-day windows counted from the start_date (no
    //              day-of-month gate; billing_day is ignored)
    //   monthly/quarterly/annual → day-of-month anchored; only fires when
    //              today is the billing_day, dedup-guarded across the period
    // The per-(student, fee, period_start) dedupe below makes every branch
    // safe to re-run daily — it never double-bills a period.
    let periodStart: Date;
    let periodEnd: Date;
    if (a.fee.type === 'one_time') {
      periodStart = start;
      periodEnd = start;
    } else if (a.fee.type === 'weekly') {
      periodStart = weeklyPeriodStart(start, todayUtc);
      periodEnd = nextPeriodStart(periodStart, 'weekly');
      periodEnd.setUTCDate(periodEnd.getUTCDate() - 1);
    } else {
      const billingDay = a.billing_day ?? start.getUTCDate();
      if (scoped) {
        // Eager: bill the period that contains today, on any day of the month.
        // today >= start (checked above) and today is within this period, so a
        // mid-cycle join bills the full current period; dedupe stops the
        // scheduled run from re-billing it on the billing day.
        periodStart = currentPeriodStart(todayUtc, a.fee.type, billingDay);
      } else {
        // Scheduled cron: only issue on the billing day, and never for a period
        // that started before the assignment.
        if (todayUtc.getUTCDate() !== billingDay) continue;
        periodStart = anchorPeriodStart(todayUtc, a.fee.type, billingDay);
        if (periodStart < start) continue;
      }
      periodEnd = nextPeriodStart(periodStart, a.fee.type);
      periodEnd.setUTCDate(periodEnd.getUTCDate() - 1);
    }

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
  filter: Filter,
): Promise<Assignment[]> {
  // A batch-scoped run (a batch-fee trigger) has no student-level component.
  if (filter.batchId && !filter.studentId) return [];

  let q = admin
    .from('student_fee_assignments')
    .select('academy_id, student_id, fee_structure_id, start_date, '
        + 'end_date, billing_day, '
        + 'fee:fee_structure_id(type, base_amount, tax_pct, name)')
    .eq('is_active', true);
  if (filter.studentId) q = q.eq('student_id', filter.studentId);
  if (filter.academyId) q = q.eq('academy_id', filter.academyId);

  const { data } = await q;
  return ((data ?? []) as unknown as Assignment[])
    .filter((r) => r.fee !== null);
}

async function collectBatchLevel(
  admin: ReturnType<typeof createClient>,
  filter: Filter,
): Promise<Assignment[]> {
  // When scoped to a single student, restrict to the batches they're actually
  // enrolled in (and emit only that student below).
  let restrictBatchIds: string[] | null = null;
  if (filter.studentId && !filter.batchId) {
    const { data: enrolls } = await admin
      .from('batch_enrollments')
      .select('batch_id')
      .eq('student_id', filter.studentId)
      .eq('enrollment_status', 'active');
    restrictBatchIds = ((enrolls ?? []) as Array<{ batch_id: string }>)
      .map((e) => e.batch_id);
    if (restrictBatchIds.length === 0) return [];
  }

  // Batch-level fee assignments + active enrollments → expand to per-student
  // pseudo-assignments that share the per-student code path.
  let q = admin
    .from('batch_fee_assignments')
    .select('academy_id, batch_id, fee_structure_id, start_date, '
        + 'end_date, billing_day, '
        + 'fee:fee_structure_id(type, base_amount, tax_pct, name)')
    .eq('is_active', true);
  if (filter.batchId) q = q.eq('batch_id', filter.batchId);
  if (restrictBatchIds) q = q.in('batch_id', restrictBatchIds);
  if (filter.academyId) q = q.eq('academy_id', filter.academyId);

  const { data: bfas } = await q;

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
    let eq = admin
      .from('batch_enrollments')
      .select('student_id')
      .eq('batch_id', bfa.batch_id)
      .eq('enrollment_status', 'active');
    if (filter.studentId) eq = eq.eq('student_id', filter.studentId);
    const { data: enrolls } = await eq;
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
