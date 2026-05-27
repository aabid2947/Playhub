// Pure CSV serialization (RFC 4180). No DOM/Supabase imports → unit testable.

export type CsvColumn<T> = {
  header: string;
  value: (row: T) => string | number | boolean | null | undefined;
};

function escapeField(raw: string | number | boolean | null | undefined): string {
  if (raw === null || raw === undefined) return "";
  const s = String(raw);
  // Quote when the value contains a comma, quote, CR or LF; double inner quotes.
  if (/[",\r\n]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

export function toCsv<T>(rows: T[], columns: CsvColumn<T>[]): string {
  const head = columns.map((c) => escapeField(c.header)).join(",");
  const body = rows.map((row) =>
    columns.map((c) => escapeField(c.value(row))).join(","),
  );
  return [head, ...body].join("\r\n");
}
