// Pure aggregation helpers — no Supabase / Next imports, so they are unit
// testable in isolation and reusable by any data module.

export type MonthPoint = { month: string; value: number };

/** First-of-month key (UTC) for an ISO timestamp, e.g. "2026-05-01". */
export function monthKey(iso: string): string {
  const d = new Date(iso);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  return `${y}-${m}-01`;
}

/**
 * Sums `amount` into calendar-month buckets and emits a CONTINUOUS series for
 * the last `monthsBack` months ending this month (gaps filled with zero), so
 * charts never show holes. `now` is injectable for deterministic tests.
 */
export function bucketByMonth(
  rows: { ts: string; amount: number }[],
  monthsBack = 12,
  now: Date = new Date(),
): MonthPoint[] {
  const totals = new Map<string, number>();
  for (const r of rows) {
    const k = monthKey(r.ts);
    totals.set(k, (totals.get(k) ?? 0) + r.amount);
  }

  const out: MonthPoint[] = [];
  for (let i = monthsBack - 1; i >= 0; i -= 1) {
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
    const k = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-01`;
    out.push({ month: k, value: totals.get(k) ?? 0 });
  }
  return out;
}

/** Outstanding balance on a SaaS invoice (total billed minus paid). */
export function invoiceOutstanding(i: {
  total_amount: number | null;
  amount: number;
  tax_amount: number;
  amount_paid: number;
}): number {
  const total = i.total_amount ?? Number(i.amount) + Number(i.tax_amount);
  return Number(total) - Number(i.amount_paid ?? 0);
}
