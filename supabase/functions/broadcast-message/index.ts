// Coach/admin broadcasts a message into a batch group thread.
//
// Body: { batch_id, content, attachments?: string[] }
//
// Behaviour:
//   1. Calls ensure_batch_thread(batch_id) which creates / refreshes the
//      thread + participant set.
//   2. Inserts a `messages` row signed by the caller.
//   3. Inserts in-app notifications for every participant except the sender.
//   4. Pushes via FCM to participants' device tokens.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm.ts';

interface Body {
  batch_id: string;
  content: string;
  attachments?: string[];
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
  if (!body?.batch_id || !body?.content) {
    return j({ error: 'batch_id + content required' }, 400);
  }

  // 1. Ensure thread + participants. Run as the caller so RLS can enforce
  // same-academy.
  const callerClient = createClient(url, anon, {
    global: { headers: { authorization: `Bearer ${token}` } },
  });

  const { data: threadId, error: rpcErr } = await callerClient
    .rpc('ensure_batch_thread', { p_batch_id: body.batch_id });
  if (rpcErr || !threadId) {
    return j({ error: rpcErr?.message ?? 'thread create failed' }, 400);
  }

  // 2. Resolve caller's user id + academy via the auth token.
  const { data: ures } = await callerClient.auth.getUser();
  const senderId = ures.user?.id;
  if (!senderId) return j({ error: 'unauthorised' }, 401);

  const admin = createClient(url, key);
  const { data: senderRow } = await admin.from('users')
    .select('academy_id').eq('id', senderId).single();
  const academyId = senderRow?.academy_id;
  if (!academyId) return j({ error: 'sender has no academy' }, 400);

  // 3. Insert the message via service role (RLS already verified above).
  const { data: msg, error: msgErr } = await admin.from('messages').insert({
    thread_id: threadId,
    academy_id: academyId,
    sender_id: senderId,
    content: body.content,
    attachments: body.attachments ?? [],
  }).select('id').single();
  if (msgErr) return j({ error: msgErr.message }, 400);

  // 4. Fan-out notifications + push (skip the sender).
  const { data: parts } = await admin.from('thread_participants')
    .select('user_id').eq('thread_id', threadId).neq('user_id', senderId);
  const recipientIds = (parts ?? []).map(p => p.user_id);
  if (recipientIds.length === 0) {
    return j({ ok: true, message_id: msg.id, recipients: 0 });
  }

  await admin.from('notifications').insert(recipientIds.map(uid => ({
    user_id: uid,
    academy_id: academyId,
    category: 'message',
    title: 'New batch message',
    body: body.content.slice(0, 200),
    deep_link: `/threads/${threadId}`,
    entity_type: 'messages',
    entity_id: msg.id,
  })));

  const { data: tokens } = await admin.from('device_tokens')
    .select('fcm_token').in('user_id', recipientIds);
  const list = (tokens ?? []).map(t => t.fcm_token);
  if (list.length > 0) {
    try {
      const r = await sendPush(list, {
        title: 'Batch message',
        body: body.content.slice(0, 200),
        deep_link: `/threads/${threadId}`,
      });
      if (r.invalid_tokens.length > 0) {
        await admin.from('device_tokens')
          .delete().in('fcm_token', r.invalid_tokens);
      }
    } catch (err) {
      console.error('FCM push failed', err);
    }
  }

  return j({
    ok: true, thread_id: threadId, message_id: msg.id,
    recipients: recipientIds.length,
  });
});

function j(b: unknown, status = 200) {
  return new Response(JSON.stringify(b),
    { status, headers: { ...corsHeaders, 'content-type': 'application/json' } });
}
