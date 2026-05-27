import { describe, it, expect } from "vitest";
import { monthKey, bucketByMonth, invoiceOutstanding } from "@/lib/aggregate";

describe("monthKey", () => {
  it("returns the first-of-month UTC key", () => {
    expect(monthKey("2026-05-27T18:30:00Z")).toBe("2026-05-01");
    expect(monthKey("2026-01-01T00:00:00Z")).toBe("2026-01-01");
  });
});

describe("bucketByMonth", () => {
  const now = new Date(Date.UTC(2026, 4, 15)); // 2026-05-15

  it("emits a continuous, gap-filled series of the right length", () => {
    const series = bucketByMonth([], 12, now);
    expect(series).toHaveLength(12);
    expect(series[0].month).toBe("2025-06-01");
    expect(series[11].month).toBe("2026-05-01");
    expect(series.every((p) => p.value === 0)).toBe(true);
  });

  it("sums amounts into the correct month bucket", () => {
    const series = bucketByMonth(
      [
        { ts: "2026-05-02T00:00:00Z", amount: 100 },
        { ts: "2026-05-20T00:00:00Z", amount: 50 },
        { ts: "2026-04-10T00:00:00Z", amount: 30 },
      ],
      12,
      now,
    );
    const may = series.find((p) => p.month === "2026-05-01");
    const apr = series.find((p) => p.month === "2026-04-01");
    expect(may?.value).toBe(150);
    expect(apr?.value).toBe(30);
  });

  it("ignores rows outside the window", () => {
    const series = bucketByMonth(
      [{ ts: "2020-01-01T00:00:00Z", amount: 999 }],
      12,
      now,
    );
    expect(series.reduce((s, p) => s + p.value, 0)).toBe(0);
  });
});

describe("invoiceOutstanding", () => {
  it("uses total_amount when present", () => {
    expect(
      invoiceOutstanding({
        total_amount: 1180,
        amount: 1000,
        tax_amount: 180,
        amount_paid: 180,
      }),
    ).toBe(1000);
  });

  it("falls back to amount + tax when total_amount is null", () => {
    expect(
      invoiceOutstanding({
        total_amount: null,
        amount: 1000,
        tax_amount: 180,
        amount_paid: 0,
      }),
    ).toBe(1180);
  });
});
