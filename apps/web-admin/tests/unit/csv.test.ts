import { describe, it, expect } from "vitest";
import { toCsv, type CsvColumn } from "@/lib/csv";

type Row = { name: string; city: string | null; amount: number };

const cols: CsvColumn<Row>[] = [
  { header: "Name", value: (r) => r.name },
  { header: "City", value: (r) => r.city },
  { header: "Amount", value: (r) => r.amount },
];

describe("toCsv", () => {
  it("emits a header row and CRLF-joined data rows", () => {
    const csv = toCsv(
      [{ name: "Ace", city: "Pune", amount: 100 }],
      cols,
    );
    expect(csv).toBe("Name,City,Amount\r\nAce,Pune,100");
  });

  it("quotes fields containing commas, quotes, or newlines", () => {
    const csv = toCsv(
      [{ name: 'Smith, "Ace" & Co', city: "line1\nline2", amount: 0 }],
      cols,
    );
    // comma + embedded quotes → wrapped and quotes doubled; newline → wrapped
    expect(csv).toBe(
      'Name,City,Amount\r\n"Smith, ""Ace"" & Co","line1\nline2",0',
    );
  });

  it("renders null/undefined as empty fields", () => {
    const csv = toCsv([{ name: "Solo", city: null, amount: 5 }], cols);
    expect(csv).toBe("Name,City,Amount\r\nSolo,,5");
  });

  it("handles an empty dataset (header only)", () => {
    expect(toCsv<Row>([], cols)).toBe("Name,City,Amount");
  });
});
