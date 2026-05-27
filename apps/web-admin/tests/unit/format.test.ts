import { describe, it, expect } from "vitest";
import {
  inr,
  inrPrecise,
  fmtDate,
  fmtDateTime,
  fmtMonth,
  humanize,
} from "@/lib/format";

describe("inr", () => {
  it("formats whole rupees with the ₹ symbol and Indian grouping", () => {
    // en-IN groups as 12,34,567 (lakh/crore), not 1,234,567.
    expect(inr(1234567)).toBe("₹12,34,567");
  });
  it("treats null/undefined as zero", () => {
    expect(inr(null)).toBe("₹0");
    expect(inr(undefined)).toBe("₹0");
  });
  it("rounds to whole rupees", () => {
    expect(inr(99.4)).toBe("₹99");
  });
});

describe("inrPrecise", () => {
  it("keeps two decimal places", () => {
    expect(inrPrecise(1000)).toBe("₹1,000.00");
    expect(inrPrecise(1234.5)).toBe("₹1,234.50");
  });
});

describe("fmtDate / fmtDateTime", () => {
  it("renders an ISO date in IST as 'dd Mon yyyy'", () => {
    expect(fmtDate("2026-05-27T00:00:00Z")).toBe("27 May 2026");
  });
  it("returns an em dash for empty/invalid input", () => {
    expect(fmtDate(null)).toBe("—");
    expect(fmtDate("not-a-date")).toBe("—");
    expect(fmtDateTime(undefined)).toBe("—");
  });
  it("includes a time component for datetimes", () => {
    expect(fmtDateTime("2026-05-27T09:00:00Z")).toMatch(/27 May 2026/);
  });
});

describe("fmtMonth", () => {
  it("renders a month_start date as 'Mon yy'", () => {
    expect(fmtMonth("2026-05-01")).toBe("May 26");
  });
  it("returns an em dash for nullish input", () => {
    expect(fmtMonth(null)).toBe("—");
  });
});

describe("humanize", () => {
  it("title-cases snake_case enums", () => {
    expect(humanize("past_due")).toBe("Past Due");
    expect(humanize("waiting_on_user")).toBe("Waiting On User");
    expect(humanize("active")).toBe("Active");
  });
  it("returns an em dash for nullish input", () => {
    expect(humanize(null)).toBe("—");
    expect(humanize(undefined)).toBe("—");
  });
});
