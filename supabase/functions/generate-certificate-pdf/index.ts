// Caller-triggered: renders an event-participation certificate as a real
// PDF via pdf-lib, uploads it into the `certificates` bucket, stamps
// event_results.certificate_url + certificate_issued_at, and returns a
// signed URL valid for 10 minutes.
//
// Body: { result_id }
// Caller must be able to read the event_result row (RLS gates this).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import {
  drawCenteredBlock,
  drawFooter,
  drawRule,
  finalizePdf,
  startPdf,
} from '../_shared/pdf.ts';

interface Body { result_id: string }

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
  if (!body?.result_id) return j({ error: 'result_id required' }, 400);

  const caller = createClient(url, anonKey, {
    global: { headers: { authorization: auth } },
  });

  const { data: result, error } = await caller
    .from('event_results')
    .select(
      'id, academy_id, event_id, student_id, placement, score, '
      + 'category, remarks, certificate_url, '
      + 'event:event_id(title, kind, sport, starts_at, location), '
      + 'student:student_id(first_name, last_name, parent_name)',
    )
    .eq('id', body.result_id)
    .single();
  if (error || !result) return j({ error: 'result not found' }, 404);

  const { data: academy } = await caller
    .from('academies')
    .select('name, email, phone')
    .eq('id', result.academy_id)
    .single();

  const event = result.event as
    | { title: string; kind: string; sport: string | null; starts_at: string; location: string | null }
    | null;
  const student = result.student as
    | { first_name: string; last_name: string; parent_name: string }
    | null;

  const placementLabel = result.placement
    ? ordinal(result.placement)
    : (result.score != null ? `Score: ${result.score}` : 'Participation');

  const ctx = await startPdf();
  // Push the headline down a third of the page for visual weight.
  ctx.cursorY -= 60;
  drawCenteredBlock(ctx, [
    { text: 'CERTIFICATE OF ACHIEVEMENT', size: 22, bold: true, color: 'accent', gap: 36 },
    { text: 'This is to certify that', size: 12, color: 'muted', gap: 22 },
    {
      text: `${student?.first_name ?? ''} ${student?.last_name ?? ''}`.trim() || '—',
      size: 28,
      bold: true,
      gap: 32,
    },
    { text: 'has participated in', size: 12, color: 'muted', gap: 22 },
    { text: event?.title ?? '—', size: 18, bold: true, gap: 14 },
    {
      text: [event?.kind, event?.sport].filter(Boolean).join(' · ') || '',
      size: 11,
      color: 'muted',
      gap: 12,
    },
    {
      text: [
        (event?.starts_at ?? '').substring(0, 10),
        event?.location,
        result.category,
      ].filter(Boolean).join(' · '),
      size: 11,
      color: 'muted',
      gap: 32,
    },
    { text: 'Achievement', size: 10, color: 'muted', gap: 14 },
    { text: placementLabel, size: 16, bold: true, color: 'accent', gap: 30 },
  ]);

  if (result.remarks) {
    drawCenteredBlock(ctx, [
      { text: result.remarks, size: 10, color: 'muted', gap: 24 },
    ]);
  }

  ctx.cursorY -= 12;
  drawRule(ctx);
  drawCenteredBlock(ctx, [
    { text: 'Issued by', size: 9, color: 'muted', gap: 14 },
    { text: academy?.name ?? '', size: 12, bold: true, gap: 12 },
    {
      text: `Issued on ${new Date().toISOString().substring(0, 10)}`,
      size: 9,
      color: 'muted',
      gap: 16,
    },
  ]);

  drawFooter(ctx, 'PlayHub · digital certificate');
  const bytes = await finalizePdf(ctx);

  const admin = createClient(url, serviceKey);
  const path = `${result.academy_id}/${result.event_id}/${result.id}-${Date.now()}.pdf`;

  const { error: uErr } = await admin.storage
    .from('certificates')
    .upload(path, bytes, { contentType: 'application/pdf', upsert: true });
  if (uErr) return j({ error: uErr.message }, 500);

  const { data: signed, error: sErr } = await admin.storage
    .from('certificates').createSignedUrl(path, 600);
  if (sErr) return j({ error: sErr.message }, 500);

  await admin
    .from('event_results')
    .update({
      certificate_url: path,
      certificate_issued_at: new Date().toISOString(),
    })
    .eq('id', result.id);

  return j({
    ok: true,
    storage_path: path,
    signed_url: signed?.signedUrl,
    expires_in: 600,
  });
});

function ordinal(n: number): string {
  const s = ['th', 'st', 'nd', 'rd'];
  const v = n % 100;
  return n + (s[(v - 20) % 10] ?? s[v] ?? s[0]) + ' Place';
}

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
