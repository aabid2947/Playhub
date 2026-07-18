// Fans an announcement out to its target audience.
//
// Triggered by:
//   - admin "Send now" → POST { announcement_id }, auth required
//   - cron (later) for scheduled_for in the past
//
// Flow:
//   1. Load the announcement (must not be sent already).
//   2. Resolve target users from target_roles + target_batches + target_centers.
//      Empty targets = everyone in the academy.
//   3. Insert announcement_recipients (one per target, idempotent).
//   4. Per channel:
//      - in_app:  insert into notifications
//      - push:    look up device_tokens, send via FCM
//      - email:   look up users.email, send via Gmail SMTP
//   5. Update announcements.sent_at + sent_count + failed_count.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight, authoriseCron } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm.ts';
import { sendEmail } from '../_shared/email.ts';

interface Body { announcement_id: string }

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  // Allow either an authenticated admin call OR a cron call.
  const auth = req.headers.get('authorization') ?? '';
  if (!auth.toLowerCase().startsWith('bearer ')) {
    const denied = authoriseCron(req);
    if (denied) return denied;
  }

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return j({ error: 'missing env' }, 500);
  const admin = createClient(url, key);

  const body = await req.json().catch(() => null) as Body | null;
  if (!body?.announcement_id) return j({ error: 'announcement_id required' }, 400);

  const { data: ann, error: annErr } = await admin
    .from('announcements')
    .select(
      'id, academy_id, subject, body, created_by, target_roles, '
      + 'target_batches, target_centers, target_sports, '
      + 'via_push, via_email, via_in_app, sent_at',
    )
    .eq('id', body.announcement_id).single();
  if (annErr || !ann) return j({ error: 'announcement not found' }, 404);
  if (ann.sent_at) return j({ error: 'already sent' }, 409);

  // Resolve the target user set ----------------------------------------
  const userIds = await resolveTargets(admin, ann);
  if (userIds.size === 0) {
    await admin.from('announcements').update({
      sent_at: new Date().toISOString(),
      sent_count: 0, failed_count: 0,
    }).eq('id', ann.id);
    return j({ ok: true, sent_count: 0 });
  }

  // Recipients: idempotent insert.
  const recipientRows = [...userIds].map(u => ({
    academy_id: ann.academy_id,
    announcement_id: ann.id,
    user_id: u,
  }));
  await admin.from('announcement_recipients').upsert(recipientRows,
    { onConflict: 'announcement_id,user_id' });

  // In-app notifications ------------------------------------------------
  if (ann.via_in_app) {
    await admin.from('notifications').insert([...userIds].map(u => ({
      user_id: u,
      academy_id: ann.academy_id,
      category: 'announcement',
      title: ann.subject,
      body: ann.body,
      deep_link: `/announcements/${ann.id}`,
      entity_type: 'announcements',
      entity_id: ann.id,
    })));
  }

  let sent_ok = userIds.size;
  let failed = 0;

  // Push (FCM) ----------------------------------------------------------
  if (ann.via_push) {
    const { data: tokens } = await admin
      .from('device_tokens')
      .select('fcm_token, user_id')
      .in('user_id', [...userIds]);

    const list = (tokens ?? []).map(t => t.fcm_token);
    if (list.length > 0) {
      try {
        const r = await sendPush(list, {
          title: ann.subject,
          body: ann.body,
          deep_link: `/announcements/${ann.id}`,
        });
        failed += r.failed;
        if (r.invalid_tokens.length > 0) {
          await admin.from('device_tokens')
            .delete().in('fcm_token', r.invalid_tokens);
        }
      } catch (err) {
        console.error('FCM fan-out failed', err);
        failed += list.length;
      }
    }
  }

  // Email ---------------------------------------------------------------
  if (ann.via_email) {
    const { data: users } = await admin
      .from('users').select('email')
      .in('id', [...userIds]).not('email', 'is', null);

    for (const u of users ?? []) {
      if (!u.email) continue;
      const ok = await sendEmail({
        to: u.email,
        subject: ann.subject,
        body_text: ann.body,
      });
      if (!ok) failed++;
    }
  }

  await admin.from('announcements').update({
    sent_at: new Date().toISOString(),
    sent_count: sent_ok,
    failed_count: failed,
  }).eq('id', ann.id);

  return j({ ok: true, sent_count: sent_ok, failed_count: failed });
});

interface Announcement {
  academy_id: string;
  created_by: string | null;
  target_roles: string[];
  target_batches: string[];
  target_centers: string[];
  target_sports: string[];
}

// Batch / sport / center targeting all resolve to the FAMILIES in that scope:
// enrolled students' own logins (when linked) + their parents. Role targeting
// (admin-only, validated by can_target_announcement) is the way to reach staff.
async function resolveTargets(
  admin: ReturnType<typeof createClient>,
  ann: Announcement,
): Promise<Set<string>> {
  const out = new Set<string>();
  const roles = ann.target_roles ?? [];
  const batches = [...(ann.target_batches ?? [])];
  const centers = ann.target_centers ?? [];
  const sports = ann.target_sports ?? [];

  if (roles.length === 0 && batches.length === 0
    && centers.length === 0 && sports.length === 0) {
    const { data } = await admin.from('users').select('id')
      .eq('academy_id', ann.academy_id).eq('is_active', true);
    (data ?? []).forEach(u => out.add(u.id));
    return out;
  }

  // Role-targeted users in the academy.
  if (roles.length > 0) {
    const { data } = await admin.from('users').select('id')
      .eq('academy_id', ann.academy_id).eq('is_active', true)
      .in('role', roles);
    (data ?? []).forEach(u => out.add(u.id));
  }

  // Sport targeting → batches of that sport. Scope the resolution to the
  // creator's center when the creator is center-bound (center_admin /
  // head_coach), so a center-scoped sport post can't reach other centers.
  if (sports.length > 0) {
    let creatorCenter: string | null = null;
    if (ann.created_by) {
      const { data: creator } = await admin.from('users')
        .select('role, center_id').eq('id', ann.created_by).maybeSingle();
      if (creator && (creator.role === 'center_admin' || creator.role === 'head_coach')) {
        creatorCenter = creator.center_id as string | null;
      }
    }
    let q = admin.from('batches').select('id')
      .eq('academy_id', ann.academy_id).in('sport_id', sports);
    if (creatorCenter) q = q.eq('center_id', creatorCenter);
    const { data } = await q;
    (data ?? []).forEach(b => batches.push((b as { id: string }).id));
  }

  // Collect the student set across batch + center targeting.
  const studentIds = new Set<string>();

  if (batches.length > 0) {
    const { data } = await admin.from('batch_enrollments')
      .select('student_id')
      .in('batch_id', batches)
      .eq('enrollment_status', 'active');
    (data ?? []).forEach(e => studentIds.add((e as { student_id: string }).student_id));
  }

  if (centers.length > 0) {
    const { data } = await admin.from('students').select('id')
      .eq('academy_id', ann.academy_id).in('center_id', centers);
    (data ?? []).forEach(s => studentIds.add((s as { id: string }).id));
  }

  // Resolve students → their own logins + their parents.
  if (studentIds.size > 0) {
    const ids = [...studentIds];
    const { data: students } = await admin.from('students')
      .select('user_id').in('id', ids).not('user_id', 'is', null);
    (students ?? []).forEach(s => {
      const uid = (s as { user_id: string | null }).user_id;
      if (uid) out.add(uid);
    });

    const { data: parents } = await admin.from('parent_links')
      .select('parent_user_id').in('student_id', ids);
    (parents ?? []).forEach(p => out.add((p as { parent_user_id: string }).parent_user_id));
  }

  return out;
}

function j(b: unknown, status = 200) {
  return new Response(JSON.stringify(b),
    { status, headers: { ...corsHeaders, 'content-type': 'application/json' } });
}
