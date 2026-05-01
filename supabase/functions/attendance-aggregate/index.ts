// Cron-triggered: refreshes the two attendance/performance materialized
// views. Wire it via pg_cron + pg_net on the remote project, or invoke
// manually with the service-role key.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const denied = authoriseCron(req);
  if (denied) return denied;

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    return new Response(
      JSON.stringify({ error: 'missing SUPABASE_URL or SERVICE_ROLE_KEY' }),
      { status: 500, headers: { ...corsHeaders, 'content-type': 'application/json' } },
    );
  }

  const supabase = createClient(url, key);
  const { error } = await supabase.rpc('refresh_attendance_aggregates');
  if (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'content-type': 'application/json' } },
    );
  }
  return new Response(
    JSON.stringify({ ok: true, refreshed_at: new Date().toISOString() }),
    { headers: { ...corsHeaders, 'content-type': 'application/json' } },
  );
});
