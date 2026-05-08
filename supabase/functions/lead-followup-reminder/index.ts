// Cron — daily ~09:00 IST: nudge whoever owns each lead whose
// next_followup_at has passed and which is still in an open status.
//
// For each eligible lead:
//   - insert a notifications row for assigned_to (or the academy owner if
//     unassigned)
//   - push via FCM
//   - log a lead_activities row of kind='reminder_sent'
//
// Idempotency: we only fire once per (lead_id, due-date). Implemented by
// checking lead_activities for an existing reminder_sent row whose
// metadata.due_at matches the lead's next_followup_at value.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { authoriseCron, corsHeaders, preflight } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const denied = authoriseCron(req);
  if (denied) return denied;

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return j({ error: 'missing env' }, 500);
  const admin = createClient(url, key);

  const { data: leads } = await admin.from('leads')
    .select('id, academy_id, first_name, last_name, sport, '
      + 'assigned_to, next_followup_at, status')
    .not('next_followup_at', 'is', null)
    .lte('next_followup_at', new Date().toISOString())
    .not('status', 'in', '("converted","lost")');

  let pushed = 0;

  for (const l of leads ?? []) {
    // Owner fallback if unassigned.
    let recipientId = l.assigned_to as string | null;
    if (!recipientId) {
      const { data: owner } = await admin.from('users').select('id')
        .eq('academy_id', l.academy_id)
        .eq('role', 'academy_owner').limit(1).maybeSingle();
      recipientId = owner?.id ?? null;
    }
    if (!recipientId) continue;

    // Idempotency check: already reminded for this due_at?
    const { data: existing } = await admin.from('lead_activities')
      .select('id').eq('lead_id', l.id).eq('kind', 'reminder_sent')
      .filter('metadata->>due_at', 'eq', l.next_followup_at)
      .limit(1).maybeSingle();
    if (existing) continue;

    const title = 'Lead follow-up due';
    const body = `${l.first_name} ${l.last_name ?? ''}`.trim()
      + (l.sport ? ` — ${l.sport}` : '');

    await admin.from('notifications').insert({
      user_id: recipientId,
      academy_id: l.academy_id,
      category: 'lead',
      title, body,
      deep_link: `/leads/${l.id}`,
      entity_type: 'leads', entity_id: l.id,
    });

    const { data: toks } = await admin.from('device_tokens')
      .select('fcm_token').eq('user_id', recipientId);
    const list = (toks ?? []).map(t => t.fcm_token);
    if (list.length > 0) {
      try {
        await sendPush(list, { title, body, deep_link: `/leads/${l.id}` });
      } catch (err) { console.error('FCM failed for lead reminder', err); }
    }

    await admin.from('lead_activities').insert({
      academy_id: l.academy_id, lead_id: l.id, user_id: null,
      kind: 'reminder_sent',
      content: 'Follow-up due reminder sent',
      metadata: { due_at: l.next_followup_at, recipient_id: recipientId },
    });

    pushed++;
  }

  return j({ ok: true, leads_reminded: pushed });
});

function j(b: unknown, status = 200) {
  return new Response(JSON.stringify(b),
    { status, headers: { ...corsHeaders, 'content-type': 'application/json' } });
}
