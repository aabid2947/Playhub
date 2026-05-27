// India-first formatting helpers. PlayHub is INR + Asia/Kolkata everywhere.

const INR = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  maximumFractionDigits: 0,
});

const INR_PRECISE = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** ₹12,345 — whole rupees (dashboards, KPI cards). */
export function inr(amount: number | null | undefined): string {
  return INR.format(amount ?? 0);
}

/** ₹12,345.00 — paise precision (invoices, payments). */
export function inrPrecise(amount: number | null | undefined): string {
  return INR_PRECISE.format(amount ?? 0);
}

const DATE = new Intl.DateTimeFormat("en-IN", {
  timeZone: "Asia/Kolkata",
  day: "2-digit",
  month: "short",
  year: "numeric",
});

const DATETIME = new Intl.DateTimeFormat("en-IN", {
  timeZone: "Asia/Kolkata",
  day: "2-digit",
  month: "short",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

/** 27 May 2026 (IST). */
export function fmtDate(value: string | Date | null | undefined): string {
  if (!value) return "—";
  const d = typeof value === "string" ? new Date(value) : value;
  if (Number.isNaN(d.getTime())) return "—";
  return DATE.format(d);
}

/** 27 May 2026, 02:30 pm (IST). */
export function fmtDateTime(value: string | Date | null | undefined): string {
  if (!value) return "—";
  const d = typeof value === "string" ? new Date(value) : value;
  if (Number.isNaN(d.getTime())) return "—";
  return DATETIME.format(d);
}

/** "month_start" rows from analytics MVs are date strings → "May 2026". */
export function fmtMonth(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("en-IN", {
    timeZone: "Asia/Kolkata",
    month: "short",
    year: "2-digit",
  }).format(d);
}

/** snake_case enum → "Title Case" for display. */
export function humanize(value: string | null | undefined): string {
  if (!value) return "—";
  return value
    .split("_")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}
