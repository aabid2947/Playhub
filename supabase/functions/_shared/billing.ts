// Pure billing/period math shared by the cron + payment Edge Functions.
// Extracted here so it is unit-testable in isolation (no DB, no network):
//   - recur-invoice-generation: period windows + discount clamping
//   - recur-saas-billing:        next period end
//   - mark-overdue:              late-fee accrual
//   - create-razorpay-order:     rupees → paise
// Keep behaviour identical to the call sites; tests pin every branch.

export function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Rupees → integer paise, as Razorpay's Orders API expects. */
export function toPaise(amountRupees: number): number {
  return Math.round(amountRupees * 100);
}

// ── SaaS billing period (recur-saas-billing) ────────────────────────────────
export function nextPeriodEnd(start: Date, cycle: "monthly" | "yearly"): Date {
  const d = new Date(start);
  if (cycle === "yearly") d.setUTCFullYear(d.getUTCFullYear() + 1);
  else d.setUTCMonth(d.getUTCMonth() + 1);
  return d;
}

// ── Recurring invoice periods (recur-invoice-generation) ────────────────────
export type FeeType = "weekly" | "monthly" | "quarterly" | "annual" | "one_time";

/**
 * Start of the billing period that `today` falls in, anchored on billingDay
 * (a day-of-month, 1–28). Only meaningful for day-of-month-anchored types
 * (monthly/quarterly/annual). Weekly anchors on a weekday relative to the
 * assignment start, so the cron uses `weeklyPeriodStart` instead — do NOT pass
 * "weekly" or "one_time" here.
 */
export function anchorPeriodStart(today: Date, type: FeeType, billingDay: number): Date {
  const d = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), billingDay));
  if (type === "monthly") return d;
  if (type === "quarterly") {
    const q = Math.floor(today.getUTCMonth() / 3) * 3;
    return new Date(Date.UTC(today.getUTCFullYear(), q, billingDay));
  }
  return new Date(Date.UTC(today.getUTCFullYear(), 0, billingDay));
}

/**
 * Start of the rolling 7-day weekly period containing `today`, counted in whole
 * weeks from `start` (the assignment start date). Weekly fees have no
 * day-of-month billing_day — periods always align to the start date's weekday.
 */
export function weeklyPeriodStart(start: Date, today: Date): Date {
  const msPerWeek = 7 * 86_400_000;
  const weeks = Math.max(0, Math.floor((today.getTime() - start.getTime()) / msPerWeek));
  const d = new Date(start);
  d.setUTCDate(d.getUTCDate() + weeks * 7);
  return d;
}

export function nextPeriodStart(start: Date, type: FeeType): Date {
  const d = new Date(start);
  if (type === "weekly") d.setUTCDate(d.getUTCDate() + 7);
  else if (type === "monthly") d.setUTCMonth(d.getUTCMonth() + 1);
  else if (type === "quarterly") d.setUTCMonth(d.getUTCMonth() + 3);
  else d.setUTCFullYear(d.getUTCFullYear() + 1);
  return d;
}

/** Inclusive last day of the period that begins at periodStart. */
export function periodEndFor(periodStart: Date, type: FeeType): Date {
  const e = nextPeriodStart(periodStart, type);
  e.setUTCDate(e.getUTCDate() - 1);
  return e;
}

export function isoDate(d: Date): string {
  return d.toISOString().substring(0, 10);
}

// ── Late fee (mark-overdue) ─────────────────────────────────────────────────
export type LateFeePolicy = "none" | "one_time" | "daily";

/** Whole days past the grace cutoff, floored at 1 (matches mark-overdue). */
export function daysLateSinceGrace(graceUntil: Date, today: Date): number {
  return Math.max(1, Math.floor((today.getTime() - graceUntil.getTime()) / 86_400_000) + 1);
}

/**
 * Fee owed up to `daysLate` days late, and the delta over what's already been
 * charged. `one_time` → one period; `daily` → one period per day late.
 * Flat amount wins over pct; pct is of base_amount.
 */
export function computeLateFee(args: {
  policy: LateFeePolicy;
  baseAmount: number;
  lateFeePct: number | null;
  lateFeeFlat: number | null;
  daysLate: number;
  alreadyCharged: number;
}): { perPeriod: number; periods: number; targetFee: number; delta: number } {
  const periods = args.policy === "daily" ? args.daysLate : 1;
  const perPeriod = args.lateFeeFlat ??
    (args.lateFeePct ? round2(args.baseAmount * args.lateFeePct / 100) : 0);
  const targetFee = round2(perPeriod * periods);
  const delta = round2(targetFee - args.alreadyCharged);
  return { perPeriod, periods, targetFee, delta };
}

// ── Discount clamping (recur-invoice-generation) ────────────────────────────
export interface DiscountStructure {
  id: string;
  name: string;
  type: "percentage" | "flat";
  value: number;
}
export interface AppliedDiscount {
  source: "student" | "batch";
  discount: DiscountStructure;
}

/**
 * Resolves a list of applicable discounts into line items, clamping the
 * running total so the invoice never goes below zero (cap = base + tax).
 */
export function computeDiscounts(
  applied: AppliedDiscount[],
  baseAmount: number,
  taxAmount: number,
): { used: number; lines: Array<{ description: string; amount: number }> } {
  const cap = round2(baseAmount + taxAmount);
  let used = 0;
  const lines: Array<{ description: string; amount: number }> = [];
  for (const a of applied) {
    const nominal = a.discount.type === "percentage"
      ? round2(baseAmount * Number(a.discount.value) / 100)
      : Number(a.discount.value);
    const remaining = round2(cap - used);
    const applyAmt = Math.min(nominal, Math.max(remaining, 0));
    if (applyAmt <= 0) continue;
    used = round2(used + applyAmt);
    const valueLabel = a.discount.type === "percentage"
      ? `${a.discount.value}%`
      : `₹${a.discount.value}`;
    lines.push({
      description: `Discount: ${a.discount.name} (${valueLabel}, ${a.source})`,
      amount: applyAmt,
    });
  }
  return { used, lines };
}
