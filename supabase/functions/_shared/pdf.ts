// PDF rendering helpers used by generate-invoice-pdf,
// generate-certificate-pdf, and attendance-report-pdf. Built on pdf-lib
// (Deno-compatible via esm.sh). Single A4 page with header + key/value
// block + optional table; multi-page only kicks in for the attendance
// report's row list.

import {
  PDFDocument,
  PDFFont,
  PDFPage,
  StandardFonts,
  rgb,
} from 'https://esm.sh/pdf-lib@1.17.1';

const A4 = { width: 595.28, height: 841.89 };
const MARGIN = 40;
const INK = rgb(0.13, 0.13, 0.15);
const MUTED = rgb(0.45, 0.47, 0.52);
const ACCENT = rgb(0.16, 0.39, 0.74);
const RULE = rgb(0.85, 0.86, 0.9);

export interface PdfContext {
  doc: PDFDocument;
  page: PDFPage;
  font: PDFFont;
  bold: PDFFont;
  cursorY: number;
}

export async function startPdf(): Promise<PdfContext> {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const page = doc.addPage([A4.width, A4.height]);
  return { doc, page, font, bold, cursorY: A4.height - MARGIN };
}

export function drawHeader(
  ctx: PdfContext,
  opts: { title: string; subtitle?: string; right?: string },
): void {
  const title = winAnsi(opts.title);
  const right = opts.right ? winAnsi(opts.right) : undefined;
  const subtitle = opts.subtitle ? winAnsi(opts.subtitle) : undefined;
  ctx.page.drawText(title, {
    x: MARGIN,
    y: ctx.cursorY - 20,
    size: 22,
    font: ctx.bold,
    color: INK,
  });
  if (right) {
    const w = ctx.bold.widthOfTextAtSize(right, 11);
    ctx.page.drawText(right, {
      x: A4.width - MARGIN - w,
      y: ctx.cursorY - 16,
      size: 11,
      font: ctx.bold,
      color: ACCENT,
    });
  }
  ctx.cursorY -= 28;
  if (subtitle) {
    ctx.page.drawText(subtitle, {
      x: MARGIN,
      y: ctx.cursorY - 14,
      size: 10,
      font: ctx.font,
      color: MUTED,
    });
    ctx.cursorY -= 18;
  }
  ctx.cursorY -= 10;
  drawRule(ctx);
}

export function drawRule(ctx: PdfContext): void {
  ctx.page.drawLine({
    start: { x: MARGIN, y: ctx.cursorY },
    end: { x: A4.width - MARGIN, y: ctx.cursorY },
    thickness: 0.6,
    color: RULE,
  });
  ctx.cursorY -= 14;
}

export function drawSectionTitle(ctx: PdfContext, label: string): void {
  ctx.cursorY -= 4;
  ctx.page.drawText(label.toUpperCase(), {
    x: MARGIN,
    y: ctx.cursorY,
    size: 9,
    font: ctx.bold,
    color: MUTED,
  });
  ctx.cursorY -= 14;
}

export function drawKv(
  ctx: PdfContext,
  pairs: Array<[string, string]>,
  opts: { columns?: 1 | 2 } = {},
): void {
  const cols = opts.columns ?? 2;
  const colWidth = (A4.width - MARGIN * 2) / cols;
  for (let i = 0; i < pairs.length; i += cols) {
    for (let c = 0; c < cols; c++) {
      const pair = pairs[i + c];
      if (!pair) continue;
      const x = MARGIN + c * colWidth;
      ctx.page.drawText(pair[0], {
        x,
        y: ctx.cursorY,
        size: 9,
        font: ctx.font,
        color: MUTED,
      });
      ctx.page.drawText(truncate(pair[1], ctx.font, 10, colWidth - 8), {
        x,
        y: ctx.cursorY - 12,
        size: 10,
        font: ctx.bold,
        color: INK,
      });
    }
    ctx.cursorY -= 30;
  }
}

export interface TableSpec {
  columns: Array<{ header: string; width: number; align?: 'left' | 'right' }>;
  rows: string[][];
}

export function drawTable(ctx: PdfContext, spec: TableSpec): void {
  const totalWidth = A4.width - MARGIN * 2;
  const colXs: number[] = [];
  let x = MARGIN;
  for (const col of spec.columns) {
    colXs.push(x);
    x += col.width * totalWidth;
  }

  // Header
  ctx.page.drawRectangle({
    x: MARGIN,
    y: ctx.cursorY - 4,
    width: totalWidth,
    height: 18,
    color: rgb(0.96, 0.97, 0.99),
  });
  for (let i = 0; i < spec.columns.length; i++) {
    const col = spec.columns[i];
    const cellW = col.width * totalWidth;
    const text = col.header;
    const align = col.align ?? 'left';
    const tx = align === 'right'
      ? colXs[i] + cellW - 6 - ctx.bold.widthOfTextAtSize(text, 9)
      : colXs[i] + 6;
    ctx.page.drawText(text.toUpperCase(), {
      x: tx,
      y: ctx.cursorY + 4,
      size: 9,
      font: ctx.bold,
      color: MUTED,
    });
  }
  ctx.cursorY -= 18;

  // Rows
  for (const row of spec.rows) {
    if (ctx.cursorY < MARGIN + 60) {
      ctx.page = ctx.doc.addPage([A4.width, A4.height]);
      ctx.cursorY = A4.height - MARGIN;
    }
    for (let i = 0; i < spec.columns.length; i++) {
      const col = spec.columns[i];
      const cellW = col.width * totalWidth;
      const raw = row[i] ?? '';
      const text = truncate(raw, ctx.font, 9, cellW - 12);
      const align = col.align ?? 'left';
      const tx = align === 'right'
        ? colXs[i] + cellW - 6 - ctx.font.widthOfTextAtSize(text, 9)
        : colXs[i] + 6;
      ctx.page.drawText(text, {
        x: tx,
        y: ctx.cursorY - 4,
        size: 9,
        font: ctx.font,
        color: INK,
      });
    }
    ctx.page.drawLine({
      start: { x: MARGIN, y: ctx.cursorY - 8 },
      end: { x: A4.width - MARGIN, y: ctx.cursorY - 8 },
      thickness: 0.4,
      color: RULE,
    });
    ctx.cursorY -= 16;
  }
  ctx.cursorY -= 8;
}

export function drawTotals(
  ctx: PdfContext,
  rows: Array<{ label: string; value: string; bold?: boolean }>,
): void {
  const right = A4.width - MARGIN;
  for (const row of rows) {
    const label = winAnsi(row.label);
    const value = winAnsi(row.value);
    const font = row.bold ? ctx.bold : ctx.font;
    const size = row.bold ? 11 : 10;
    const labelW = font.widthOfTextAtSize(label, size);
    const valueW = font.widthOfTextAtSize(value, size);
    ctx.page.drawText(label, {
      x: right - 140 - labelW + 80,
      y: ctx.cursorY,
      size,
      font,
      color: row.bold ? INK : MUTED,
    });
    ctx.page.drawText(value, {
      x: right - valueW,
      y: ctx.cursorY,
      size,
      font,
      color: row.bold ? ACCENT : INK,
    });
    ctx.cursorY -= row.bold ? 20 : 16;
  }
}

export function drawCenteredBlock(
  ctx: PdfContext,
  lines: Array<{ text: string; size: number; bold?: boolean; color?: 'ink' | 'accent' | 'muted'; gap?: number }>,
): void {
  for (const line of lines) {
    const text = winAnsi(line.text);
    const font = line.bold ? ctx.bold : ctx.font;
    const w = font.widthOfTextAtSize(text, line.size);
    const color = line.color === 'accent'
      ? ACCENT
      : line.color === 'muted' ? MUTED : INK;
    ctx.page.drawText(text, {
      x: (A4.width - w) / 2,
      y: ctx.cursorY,
      size: line.size,
      font,
      color,
    });
    ctx.cursorY -= (line.gap ?? line.size + 6);
  }
}

export function drawFooter(ctx: PdfContext, label: string): void {
  const w = ctx.font.widthOfTextAtSize(label, 8);
  ctx.page.drawText(label, {
    x: (A4.width - w) / 2,
    y: MARGIN / 2,
    size: 8,
    font: ctx.font,
    color: MUTED,
  });
}

export async function finalizePdf(ctx: PdfContext): Promise<Uint8Array> {
  return await ctx.doc.save();
}

// pdf-lib's StandardFonts (Helvetica) use WinAnsi encoding, which can only
// represent Latin-1 + a few extras. Drawing ANY other code point (Devanagari
// names, emoji, the ₹ sign, …) throws and 500s the whole request. Replace
// anything unencodable with '?' so a PDF always renders. (Full non-Latin
// rendering would need an embedded Unicode TTF via fontkit — see the note in
// generate-invoice-pdf.)
const _winAnsiExtras =
  '€‚ƒ„…†‡ˆ‰Š‹Œ'
  + 'Ž‘’“”•–—˜™š›'
  + 'œžŸ';

export function winAnsi(s: string): string {
  if (!s) return s;
  let out = '';
  for (const ch of s) {
    const code = ch.codePointAt(0) ?? 0;
    if (
      code <= 0x7f ||
      (code >= 0xa0 && code <= 0xff) ||
      _winAnsiExtras.includes(ch)
    ) {
      out += ch;
    } else {
      out += '?';
    }
  }
  return out;
}

function truncate(text: string, font: PDFFont, size: number, maxWidth: number): string {
  text = winAnsi(text);
  if (!text) return '';
  if (font.widthOfTextAtSize(text, size) <= maxWidth) return text;
  const ellipsis = '…';
  let lo = 0;
  let hi = text.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    const candidate = text.slice(0, mid) + ellipsis;
    if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return text.slice(0, Math.max(0, lo - 1)) + ellipsis;
}
