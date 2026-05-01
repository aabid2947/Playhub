// Cron daily (e.g. 09:00 IST): identifies students with <60% attendance
// over the last 30 days and returns the list grouped by academy. Designed
// to be the data source for FCM + email fan-out (which lands when those
// channels are wired in Sprint 4). For now, the response is JSON the
// caller can route to logs/Slack/Linear/etc.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';

const THRESHOLD_PCT = 60;

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

  // Refresh first so we read current numbers.
  await supabase.rpc('refresh_attendance_aggregates');

  const { data, error } = await supabase
    .from('student_attendance_summary')
    .select('academy_id, student_id, total_sessions, attendance_pct, '
        + 'last_attended_date')
    .lt('attendance_pct', THRESHOLD_PCT)
    .gte('total_sessions', 3); // ignore brand-new students

  if (error) {
    return new Response(JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'content-type': 'application/json' } });
  }

  // Group by academy for downstream fan-out
  const grouped: Record<string, unknown[]> = {};
  for (const row of (data ?? [])) {
    const k = row.academy_id as string;
    grouped[k] = grouped[k] ?? [];
    grouped[k].push(row);
  }

  return new Response(
    JSON.stringify({
      ok: true,
      threshold_pct: THRESHOLD_PCT,
      generated_at: new Date().toISOString(),
      academies: Object.keys(grouped).length,
      flagged: data?.length ?? 0,
      grouped,
    }),
    { headers: { ...corsHeaders, 'content-type': 'application/json' } },
  );
});
