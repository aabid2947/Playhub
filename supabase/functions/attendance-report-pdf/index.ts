// On-demand: generate an attendance report as a real PDF via pdf-lib.
// Caller supplies academy_id, optional batch_id, and a date range. The
// result is uploaded to a private `reports/` folder in performance_media
// and returned as a signed URL valid for 10 minutes.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import {
  drawFooter,
  drawHeader,
  drawKv,
  drawSectionTitle,
  drawTable,
  finalizePdf,
  startPdf,
} from '../_shared/pdf.ts';

interface Body {
  academy_id?: string;
  batch_id?: string;
  start_date: string; // YYYY-MM-DD
  end_date: string;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return json({ error: 'missing env' }, 500);

  const auth = req.headers.get('authorization') ?? '';
  if (!auth.toLowerCase().startsWith('bearer ')) {
    return json({ error: 'unauthorised' }, 401);
  }

  const callerClient = createClient(url, anonKey, {
    global: { headers: { authorization: auth } },
  });
  const { data: me } = await callerClient
    .from('users')
    .select('id, role, academy_id')
    .single();
  if (!me) return json({ error: 'no profile' }, 401);

  const allowedRoles = new Set(
    ['super_admin', 'academy_owner', 'academy_admin', 'center_admin', 'head_coach']);
  if (!allowedRoles.has(me.role)) return json({ error: 'forbidden' }, 403);

  const body = await req.json().catch(() => null) as Body | null;
  if (!body?.start_date || !body?.end_date) {
    return json({ error: 'start_date and end_date required' }, 400);
  }
  const academyId = body.academy_id ?? me.academy_id;
  if (academyId !== me.academy_id && me.role !== 'super_admin') {
    return json({ error: 'cross-academy not allowed' }, 403);
  }

  const adminClient = createClient(url, serviceKey);

  let q = adminClient
    .from('attendance_records')
    .select(
      'date, status, batch_id, student_id, '
      + 'students:student_id(first_name,last_name), '
      + 'batches:batch_id(name)',
    )
    .eq('academy_id', academyId)
    .gte('date', body.start_date)
    .lte('date', body.end_date)
    .order('date');
  if (body.batch_id) q = q.eq('batch_id', body.batch_id);

  const { data, error } = await q;
  if (error) return json({ error: error.message }, 500);

  const { data: academy } = await adminClient
    .from('academies')
    .select('name')
    .eq('id', academyId)
    .single();

  const rows = data ?? [];
  const counts = { present: 0, absent: 0, late: 0, excused: 0 };
  for (const r of rows) {
    const k = (r.status ?? '').toLowerCase();
    if (k in counts) counts[k as keyof typeof counts]++;
  }

  const ctx = await startPdf();
  drawHeader(ctx, {
    title: academy?.name ?? 'Attendance report',
    subtitle: `${body.start_date} → ${body.end_date}`,
    right: 'ATTENDANCE',
  });

  drawSectionTitle(ctx, 'Summary');
  drawKv(ctx, [
    ['Records', String(rows.length)],
    ['Present', String(counts.present)],
    ['Late', String(counts.late)],
    ['Absent', String(counts.absent)],
    ['Excused', String(counts.excused)],
    ['Batch filter', body.batch_id ? 'Single batch' : 'All batches'],
  ]);

  drawSectionTitle(ctx, 'Records');
  drawTable(ctx, {
    columns: [
      { header: 'Date', width: 0.18 },
      { header: 'Batch', width: 0.32 },
      { header: 'Student', width: 0.34 },
      { header: 'Status', width: 0.16 },
    ],
    rows: rows.map((r) => {
      const s = r.students as { first_name: string; last_name: string } | null;
      const b = r.batches as { name: string } | null;
      return [
        String(r.date ?? ''),
        b?.name ?? '',
        s ? `${s.first_name} ${s.last_name}` : '',
        String(r.status ?? '').toUpperCase(),
      ];
    }),
  });

  drawFooter(ctx, `Generated ${new Date().toISOString().substring(0, 10)} · PlayHub`);
  const bytes = await finalizePdf(ctx);

  const path = `${academyId}/reports/attendance-${body.start_date}_${body.end_date}-${Date.now()}.pdf`;
  const { error: uploadErr } = await adminClient.storage
    .from('performance_media')
    .upload(path, bytes, { contentType: 'application/pdf', upsert: false });
  if (uploadErr) return json({ error: uploadErr.message }, 500);

  const { data: signed, error: sErr } = await adminClient.storage
    .from('performance_media')
    .createSignedUrl(path, 600);
  if (sErr) return json({ error: sErr.message }, 500);

  return json({
    ok: true,
    rows: rows.length,
    signed_url: signed?.signedUrl,
    expires_in: 600,
  });
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
