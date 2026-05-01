// On-demand: generate an attendance report (CSV in v0.5; pdf-lib
// integration lands in v1.x once we ship a real PDF template). Caller
// supplies academy_id, optional batch_id, and a date range. The result is
// uploaded to a private `reports/` folder and returned as a signed URL.
//
// Auth: requires a valid Supabase Auth JWT; the user must be admin in the
// requested academy. RLS isn't enough here — we run as service role so
// the date join can pull names — so we re-validate the caller's role.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';

interface Body {
  academy_id?: string;
  batch_id?: string;
  start_date: string; // YYYY-MM-DD
  end_date: string;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') {
    return json({ error: 'method not allowed' }, 405);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'missing env' }, 500);
  }

  const auth = req.headers.get('authorization') ?? '';
  if (!auth.toLowerCase().startsWith('bearer ')) {
    return json({ error: 'unauthorised' }, 401);
  }

  // Caller-scoped client (RLS-enforced) for the role check.
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
  if (!allowedRoles.has(me.role)) {
    return json({ error: 'forbidden' }, 403);
  }

  const body = await req.json().catch(() => null) as Body | null;
  if (!body?.start_date || !body?.end_date) {
    return json({ error: 'start_date and end_date required' }, 400);
  }
  const academyId = body.academy_id ?? me.academy_id;
  if (academyId !== me.academy_id && me.role !== 'super_admin') {
    return json({ error: 'cross-academy not allowed' }, 403);
  }

  // Service-role client for the data pull + storage write.
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

  const rows = data ?? [];
  const csv = ['date,batch,student,status'];
  for (const r of rows) {
    const sName = r.students
      ? `${r.students.first_name} ${r.students.last_name}`
      : '';
    const bName = r.batches?.name ?? '';
    csv.push([r.date, escape(bName), escape(sName), r.status].join(','));
  }
  const blob = new TextEncoder().encode(csv.join('\n'));
  const path = `${academyId}/reports/attendance-${body.start_date}_${body.end_date}-${Date.now()}.csv`;

  // We park reports in performance_media for now (private bucket, same
  // path-prefix gate). A dedicated `reports` bucket lands when v1.1 adds
  // pdf-lib rendering for true PDFs.
  const { error: uploadErr } = await adminClient.storage
    .from('performance_media')
    .upload(path, blob, { contentType: 'text/csv', upsert: false });
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

function escape(s: string) {
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}
