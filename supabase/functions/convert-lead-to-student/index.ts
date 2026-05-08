// Convert a lead → student in one atomic call.
//
// Body: {
//   lead_id: uuid,
//   batch_id?: uuid,                 // optional initial enrollment
//   parent_user_id?: uuid,           // optional parent_link
//   start_date?: 'YYYY-MM-DD'        // enrollment start (defaults to today)
// }
//
// Steps (transactional via the convert_lead RPC):
//   1. Insert public.students from the lead.
//   2. (optional) Insert batch_enrollments.
//   3. (optional) Insert parent_links.
//   4. Update leads: status='converted', converted_student_id, converted_at.
//   5. Insert lead_activities note.
//
// Returns { student_id, lead_id }.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';

interface Body {
  lead_id: string;
  batch_id?: string;
  parent_user_id?: string;
  start_date?: string;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const auth = req.headers.get('authorization') ?? '';
  if (!auth.toLowerCase().startsWith('bearer ')) {
    return j({ error: 'unauthorised' }, 401);
  }
  const token = auth.slice(7);

  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anon || !key) return j({ error: 'missing env' }, 500);

  const body = await req.json().catch(() => null) as Body | null;
  if (!body?.lead_id) return j({ error: 'lead_id required' }, 400);

  // Caller (admin) — used to verify same-academy access.
  const callerClient = createClient(url, anon, {
    global: { headers: { authorization: `Bearer ${token}` } },
  });
  const { data: leadCheck, error: leadErr } = await callerClient
    .from('leads').select('id, academy_id, status').eq('id', body.lead_id)
    .single();
  if (leadErr || !leadCheck) {
    return j({ error: 'lead not found or no access' }, 404);
  }
  if (leadCheck.status === 'converted') {
    return j({ error: 'lead already converted' }, 409);
  }

  // Service role: do the actual writes atomically via a single RPC.
  const admin = createClient(url, key);
  const { data: result, error: rpcErr } = await admin.rpc('convert_lead', {
    p_lead_id: body.lead_id,
    p_batch_id: body.batch_id ?? null,
    p_parent_user_id: body.parent_user_id ?? null,
    p_start_date: body.start_date ?? null,
  });

  if (rpcErr) return j({ error: rpcErr.message }, 400);
  return j({ ok: true, student_id: result, lead_id: body.lead_id });
});

function j(b: unknown, status = 200) {
  return new Response(JSON.stringify(b),
    { status, headers: { ...corsHeaders, 'content-type': 'application/json' } });
}
