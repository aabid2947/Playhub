// Cron hourly: refreshes the materialized views backing the KPI dashboards.
// Calls public.refresh_analytics() which runs CONCURRENTLY refresh on each.
// Output reports duration so the cron job can be tuned if it grows slow.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const denied = authoriseCron(req);
  if (denied) return denied;

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return j({ error: 'missing env' }, 500);
  const admin = createClient(url, key);

  const t0 = Date.now();
  const { error } = await admin.rpc('refresh_analytics');
  const ms = Date.now() - t0;
  if (error) return j({ error: error.message, ms }, 500);

  return j({ ok: true, refreshed_in_ms: ms });
});

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
