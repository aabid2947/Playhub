// Admin-triggered: renders an invoice as a real PDF via pdf-lib and uploads
// it to the performance_media bucket. Returns a signed URL valid for 10
// minutes.
//
// Body: { invoice_id }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import {
  drawFooter,
  drawHeader,
  drawKv,
  drawSectionTitle,
  drawTable,
  drawTotals,
  finalizePdf,
  startPdf,
} from '../_shared/pdf.ts';

interface Body { invoice_id: string }

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const auth = req.headers.get('authorization') ?? '';
  if (!auth.toLowerCase().startsWith('bearer ')) {
    return j({ error: 'unauthorised' }, 401);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return j({ error: 'missing env' }, 500);

  const body = await req.json().catch(() => null) as Body | null;
  if (!body?.invoice_id) return j({ error: 'invoice_id required' }, 400);

  const caller = createClient(url, anonKey, {
    global: { headers: { authorization: auth } },
  });
  const { data: invoice, error } = await caller
    .from('invoices')
    .select('id, academy_id, student_id, invoice_number, due_date, '
        + 'status, base_amount, tax_amount, late_fee_amount, '
        + 'discount_amount, amount, amount_paid, period_start, period_end')
    .eq('id', body.invoice_id)
    .single();
  if (error || !invoice) return j({ error: 'invoice not found' }, 404);

  const { data: lines } = await caller
    .from('invoice_line_items')
    .select('kind, description, quantity, unit_amount, total_amount')
    .eq('invoice_id', invoice.id);

  const { data: student } = await caller
    .from('students')
    .select('first_name, last_name, parent_name')
    .eq('id', invoice.student_id)
    .single();
  const { data: academy } = await caller
    .from('academies')
    .select('name, email, phone, address, city, state')
    .eq('id', invoice.academy_id)
    .single();

  const ctx = await startPdf();
  drawHeader(ctx, {
    title: academy?.name ?? 'Invoice',
    subtitle: [academy?.address, academy?.city, academy?.state]
      .filter(Boolean).join(', ') || undefined,
    right: `INVOICE ${invoice.invoice_number}`,
  });

  drawSectionTitle(ctx, 'Bill to');
  drawKv(ctx, [
    ['Student', `${student?.first_name ?? ''} ${student?.last_name ?? ''}`.trim()],
    ['Parent', student?.parent_name ?? '—'],
    ['Period', invoice.period_start && invoice.period_end
      ? `${invoice.period_start} → ${invoice.period_end}`
      : '—'],
    ['Due date', invoice.due_date ?? '—'],
    ['Status', String(invoice.status ?? '').toUpperCase()],
    ['Contact', [academy?.phone, academy?.email].filter(Boolean).join(' · ')],
  ]);

  drawSectionTitle(ctx, 'Line items');
  drawTable(ctx, {
    columns: [
      { header: 'Kind', width: 0.18 },
      { header: 'Description', width: 0.52 },
      { header: 'Qty', width: 0.08, align: 'right' },
      { header: 'Unit', width: 0.11, align: 'right' },
      { header: 'Total', width: 0.11, align: 'right' },
    ],
    rows: (lines ?? []).map((l) => [
      String(l.kind ?? ''),
      String(l.description ?? ''),
      String(l.quantity ?? ''),
      money(l.unit_amount),
      money(l.total_amount),
    ]),
  });

  const balance = Number(invoice.amount) - Number(invoice.amount_paid);
  drawTotals(ctx, [
    { label: 'Subtotal', value: money(invoice.base_amount) },
    { label: 'Tax', value: money(invoice.tax_amount) },
    { label: 'Late fee', value: money(invoice.late_fee_amount) },
    { label: 'Discount', value: `−${money(invoice.discount_amount)}` },
    { label: 'Total', value: money(invoice.amount), bold: true },
    { label: 'Paid', value: money(invoice.amount_paid) },
    { label: 'Balance', value: money(balance), bold: true },
  ]);

  drawFooter(ctx, `Generated ${new Date().toISOString().substring(0, 10)} · PlayHub`);
  const bytes = await finalizePdf(ctx);

  const admin = createClient(url, serviceKey);
  const path = `${invoice.academy_id}/invoices/${invoice.invoice_number}-${Date.now()}.pdf`;
  const { error: uErr } = await admin.storage
    .from('performance_media')
    .upload(path, bytes, { contentType: 'application/pdf', upsert: false });
  if (uErr) return j({ error: uErr.message }, 500);

  const { data: signed, error: sErr } = await admin.storage
    .from('performance_media').createSignedUrl(path, 600);
  if (sErr) return j({ error: sErr.message }, 500);

  return j({ ok: true, signed_url: signed?.signedUrl, expires_in: 600 });
});

function money(n: unknown): string {
  const v = Number(n ?? 0);
  if (!Number.isFinite(v)) return '0.00';
  return v.toFixed(2);
}

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
