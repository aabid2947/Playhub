import { assertEquals } from "jsr:@std/assert@^1.0.0";
import {
  anchorPeriodStart,
  computeDiscounts,
  computeLateFee,
  currentPeriodStart,
  daysLateSinceGrace,
  isoDate,
  nextPeriodEnd,
  nextPeriodStart,
  periodEndFor,
  round2,
  toPaise,
  weeklyPeriodStart,
} from "./billing.ts";

const utc = (y: number, m: number, d: number) => new Date(Date.UTC(y, m, d));

Deno.test("round2 rounds to 2dp", () => {
  assertEquals(round2(1.234), 1.23);
  assertEquals(round2(1.8), 1.8);
  assertEquals(round2(2000 * 18 / 100), 360);
});

Deno.test("toPaise converts rupees to integer paise", () => {
  assertEquals(toPaise(1599), 159900);
  assertEquals(toPaise(1234.5), 123450);
});

Deno.test("nextPeriodEnd: monthly + yearly", () => {
  assertEquals(nextPeriodEnd(utc(2026, 0, 15), "monthly"), utc(2026, 1, 15));
  assertEquals(nextPeriodEnd(utc(2026, 0, 15), "yearly"), utc(2027, 0, 15));
});

Deno.test("anchorPeriodStart anchors to the right period", () => {
  const today = utc(2026, 4, 20); // 2026-05-20
  assertEquals(isoDate(anchorPeriodStart(today, "monthly", 5)), "2026-05-05");
  assertEquals(isoDate(anchorPeriodStart(today, "quarterly", 5)), "2026-04-05"); // Q2 starts Apr
  assertEquals(isoDate(anchorPeriodStart(today, "annual", 5)), "2026-01-05");
});

Deno.test("nextPeriodStart + periodEndFor", () => {
  const start = utc(2026, 4, 5); // 2026-05-05
  assertEquals(isoDate(nextPeriodStart(start, "weekly")), "2026-05-12");
  assertEquals(isoDate(nextPeriodStart(start, "monthly")), "2026-06-05");
  assertEquals(isoDate(nextPeriodStart(start, "quarterly")), "2026-08-05");
  assertEquals(isoDate(nextPeriodStart(start, "annual")), "2027-05-05");
  assertEquals(isoDate(periodEndFor(start, "monthly")), "2026-06-04");
  assertEquals(isoDate(periodEndFor(start, "weekly")), "2026-05-11");
});

Deno.test("weeklyPeriodStart anchors to whole weeks from the start date", () => {
  const start = utc(2026, 4, 5); // 2026-05-05 (a Tuesday)
  // Same day → period starts that day.
  assertEquals(isoDate(weeklyPeriodStart(start, utc(2026, 4, 5))), "2026-05-05");
  // 6 days in → still the first week.
  assertEquals(isoDate(weeklyPeriodStart(start, utc(2026, 4, 11))), "2026-05-05");
  // Day 7 → second week begins.
  assertEquals(isoDate(weeklyPeriodStart(start, utc(2026, 4, 12))), "2026-05-12");
  // 20 days in → third full week (floor(20/7) = 2 → +14 days).
  assertEquals(isoDate(weeklyPeriodStart(start, utc(2026, 4, 25))), "2026-05-19");
  // Before the assignment begins → clamped to the start date.
  assertEquals(isoDate(weeklyPeriodStart(start, utc(2026, 4, 1))), "2026-05-05");
});

Deno.test("currentPeriodStart returns the period containing today", () => {
  // today AFTER this month's billing day → current month's period
  assertEquals(isoDate(currentPeriodStart(utc(2026, 5, 30), "monthly", 28)), "2026-06-28");
  // today BEFORE this month's billing day → previous month's period
  assertEquals(isoDate(currentPeriodStart(utc(2026, 5, 10), "monthly", 28)), "2026-05-28");
  // today exactly ON the billing day → that day starts the period
  assertEquals(isoDate(currentPeriodStart(utc(2026, 5, 28), "monthly", 28)), "2026-06-28");
  // quarterly: mid-quarter join bills the current quarter (Q2 starts Apr)
  assertEquals(isoDate(currentPeriodStart(utc(2026, 5, 30), "quarterly", 28)), "2026-04-28");
  // quarterly before the quarter's billing day → previous quarter (Q1 starts Jan)
  assertEquals(isoDate(currentPeriodStart(utc(2026, 3, 10), "quarterly", 28)), "2026-01-28");
  // annual before Jan billing day → previous year
  assertEquals(isoDate(currentPeriodStart(utc(2026, 0, 10), "annual", 28)), "2025-01-28");
});

Deno.test("daysLateSinceGrace floors at 1", () => {
  assertEquals(daysLateSinceGrace(utc(2026, 4, 1), utc(2026, 4, 1)), 1);
  assertEquals(daysLateSinceGrace(utc(2026, 4, 1), utc(2026, 4, 4)), 4);
  assertEquals(daysLateSinceGrace(utc(2026, 4, 1), utc(2026, 3, 30)), 1); // before grace
});

Deno.test("computeLateFee: one_time flat", () => {
  const r = computeLateFee({ policy: "one_time", baseAmount: 2000, lateFeePct: null, lateFeeFlat: 100, daysLate: 9, alreadyCharged: 0 });
  assertEquals(r.periods, 1);
  assertEquals(r.targetFee, 100);
  assertEquals(r.delta, 100);
});

Deno.test("computeLateFee: daily accrues per day, delta nets prior charge", () => {
  const r = computeLateFee({ policy: "daily", baseAmount: 2000, lateFeePct: null, lateFeeFlat: 20, daysLate: 5, alreadyCharged: 40 });
  assertEquals(r.periods, 5);
  assertEquals(r.targetFee, 100);
  assertEquals(r.delta, 60);
});

Deno.test("computeLateFee: pct of base, flat takes precedence", () => {
  const pct = computeLateFee({ policy: "one_time", baseAmount: 2000, lateFeePct: 5, lateFeeFlat: null, daysLate: 1, alreadyCharged: 0 });
  assertEquals(pct.targetFee, 100); // 5% of 2000
  const both = computeLateFee({ policy: "one_time", baseAmount: 2000, lateFeePct: 10, lateFeeFlat: 50, daysLate: 1, alreadyCharged: 0 });
  assertEquals(both.targetFee, 50); // flat wins
  const none = computeLateFee({ policy: "one_time", baseAmount: 2000, lateFeePct: null, lateFeeFlat: null, daysLate: 1, alreadyCharged: 0 });
  assertEquals(none.targetFee, 0);
});

Deno.test("computeDiscounts: single percentage", () => {
  const { used, lines } = computeDiscounts(
    [{ source: "student", discount: { id: "d", name: "Sibling", type: "percentage", value: 10 } }],
    2000, 0,
  );
  assertEquals(used, 200);
  assertEquals(lines.length, 1);
  assertEquals(lines[0].description.includes("10%"), true);
  assertEquals(lines[0].description.includes("student"), true);
});

Deno.test("computeDiscounts: clamps running total at base+tax (never negative invoice)", () => {
  const { used, lines } = computeDiscounts(
    [
      { source: "student", discount: { id: "a", name: "A", type: "flat", value: 800 } },
      { source: "batch", discount: { id: "b", name: "B", type: "flat", value: 800 } },
    ],
    1000, 0,
  );
  assertEquals(used, 1000); // 800 + clamped 200
  assertEquals(lines.length, 2);
  assertEquals(lines[1].amount, 200);
});

Deno.test("computeDiscounts: a single over-cap discount is clamped, empty list is no-op", () => {
  const over = computeDiscounts([{ source: "student", discount: { id: "x", name: "X", type: "flat", value: 5000 } }], 1000, 0);
  assertEquals(over.used, 1000);
  const none = computeDiscounts([], 1000, 0);
  assertEquals(none.used, 0);
  assertEquals(none.lines.length, 0);
});
