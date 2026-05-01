// Cron-triggered: for every batch whose scheduled session ended earlier
// today (start_time + duration), mark any actively-enrolled student
// without an attendance record as 'absent' with method='auto'.
//
// Run hourly (e.g. every 30 minutes) so each session is closed shortly
// after it ends.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';

const DOW_CODES = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const denied = authoriseCron(req);
  if (denied) return denied;

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    return new Response(
      JSON.stringify({ error: 'missing env' }),
      { status: 500, headers: { ...corsHeaders, 'content-type': 'application/json' } },
    );
  }
  const supabase = createClient(url, key);

  const now = new Date();
  // Convert to Asia/Kolkata local time for India-first market.
  const ist = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
  const ymd = ist.toISOString().substring(0, 10);
  const hhmm = ist.toISOString().substring(11, 16);
  const dow = DOW_CODES[(ist.getUTCDay() + 6) % 7];

  // Pull all active batches scheduled today.
  const { data: batches, error: bErr } = await supabase
    .from('batches')
    .select('id, academy_id, schedule')
    .eq('is_active', true);
  if (bErr) {
    return new Response(JSON.stringify({ error: bErr.message }),
      { status: 500, headers: { ...corsHeaders, 'content-type': 'application/json' } });
  }

  let inserted = 0;
  const eligible = (batches ?? []).filter((b) => {
    const days = (b.schedule?.days ?? []) as string[];
    if (!days.map((d: string) => d.toLowerCase()).includes(dow)) return false;
    const end = (b.schedule?.end_time ?? '23:59') as string;
    return hhmm >= end;
  });

  for (const b of eligible) {
    // Active enrollments on this batch
    const { data: enrolls } = await supabase
      .from('batch_enrollments')
      .select('student_id')
      .eq('batch_id', b.id)
      .eq('enrollment_status', 'active');

    // Students who already have a record today
    const { data: existing } = await supabase
      .from('attendance_records')
      .select('student_id')
      .eq('batch_id', b.id)
      .eq('date', ymd);

    const have = new Set((existing ?? []).map((r) => r.student_id));
    const missing = (enrolls ?? [])
      .map((e) => e.student_id)
      .filter((id) => !have.has(id));

    if (missing.length === 0) continue;

    const rows = missing.map((sid) => ({
      academy_id: b.academy_id,
      batch_id: b.id,
      student_id: sid,
      date: ymd,
      status: 'absent',
      method: 'auto',
    }));
    const { error: iErr } = await supabase
      .from('attendance_records')
      .upsert(rows, { onConflict: 'batch_id,student_id,date' });
    if (!iErr) inserted += rows.length;
  }

  return new Response(
    JSON.stringify({ ok: true, ymd, inserted, batches: eligible.length }),
    { headers: { ...corsHeaders, 'content-type': 'application/json' } },
  );
});
