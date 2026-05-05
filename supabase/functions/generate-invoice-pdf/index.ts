// Admin-triggered: generates an invoice "receipt" CSV (true PDF via
// pdf-lib lands in v1.x, matching the deferral pattern from
// attendance-report-pdf). Returns a signed URL valid for 10 minutes.
//
// Body: { invoice_id }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';

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

  // Caller-scoped: RLS gates by academy.
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

  const csv = [
    `# ${academy?.name ?? ''}`,
    `# ${[academy?.address, academy?.city, academy?.state].filter(Boolean).join(', ')}`,
    `# ${academy?.email ?? ''}  ${academy?.phone ?? ''}`,
    ``,
    `Invoice,${invoice.invoice_number}`,
    `Student,${student?.first_name ?? ''} ${student?.last_name ?? ''}`,
    `Parent,${student?.parent_name ?? ''}`,
    `Period,${invoice.period_start ?? ''} to ${invoice.period_end ?? ''}`,
    `Due,${invoice.due_date}`,
    `Status,${invoice.status}`,
    ``,
    `Kind,Description,Qty,Unit,Total`,
    ...((lines ?? []).map((l) =>
      [
        l.kind,
        esc(l.description),
        l.quantity,
        l.unit_amount,
        l.total_amount,
      ].join(','))),
    ``,
    `Subtotal,${invoice.base_amount}`,
    `Tax,${invoice.tax_amount}`,
    `Late fee,${invoice.late_fee_amount}`,
    `Discount,-${invoice.discount_amount}`,
    `Total,${invoice.amount}`,
    `Paid,${invoice.amount_paid}`,
    `Balance,${(Number(invoice.amount) - Number(invoice.amount_paid)).toFixed(2)}`,
  ].join('\n');

  const admin = createClient(url, serviceKey);
  const path = `${invoice.academy_id}/invoices/${invoice.invoice_number}-${Date.now()}.csv`;
  const { error: uErr } = await admin.storage
    .from('performance_media')
    .upload(path, new TextEncoder().encode(csv), {
      contentType: 'text/csv',
      upsert: false,
    });
  if (uErr) return j({ error: uErr.message }, 500);

  const { data: signed, error: sErr } = await admin.storage
    .from('performance_media').createSignedUrl(path, 600);
  if (sErr) return j({ error: sErr.message }, 500);

  return j({ ok: true, signed_url: signed?.signedUrl, expires_in: 600 });
});

function esc(s: string): string {
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
