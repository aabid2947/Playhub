// Admin-only: invite a user by email and provision them with role +
// academy + optional linking metadata (parent → student, coach → user,
// student → user).
//
// Body: {
//   email: string,
//   role: 'academy_admin' | 'center_admin' | 'head_coach'
//       | 'coach' | 'trainer' | 'parent' | 'student',
//   first_name?: string,
//   last_name?: string,
//   center_id?: uuid,                 // for center_admin assignment
//   link_to_student_id?: uuid,        // parent → student (sets parent_link)
//   link_relationship?: string,       // 'parent' / 'guardian' / etc.
//   link_coach_id?: uuid,             // coach → user (sets coaches.user_id)
//   link_student_login_id?: uuid,     // student → user (sets students.user_id)
// }
//
// Flow:
//   1. Caller must be authenticated + has_admin_or_higher() in their academy.
//   2. Validate role isn't super_admin (those are out-of-band).
//   3. Stamp academy_id from caller's profile (admins can't cross-tenant).
//   4. Call auth.admin.inviteUserByEmail with all the metadata embedded.
//      The handle_new_auth_user trigger reads it and finalises linking
//      when the recipient accepts the invite.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';

interface Body {
  email: string;
  role: string;
  first_name?: string;
  last_name?: string;
  center_id?: string;
  link_to_student_id?: string;
  link_relationship?: string;
  link_coach_id?: string;
  link_student_login_id?: string;
  redirect_to?: string;
}

const ALLOWED_ROLES = new Set([
  'academy_admin', 'center_admin', 'head_coach',
  'coach', 'trainer', 'parent', 'student',
]);

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
  if (!body?.email || !body?.role) {
    return j({ error: 'email + role required' }, 400);
  }
  if (!ALLOWED_ROLES.has(body.role)) {
    return j({ error: `role ${body.role} not invitable via this endpoint` }, 400);
  }

  // Verify the caller via the documented Edge-Function pattern: pass the
  // JWT directly to getUser so it doesn't try to read a non-existent
  // local session. Then re-create a callerClient with the auth header
  // set for downstream RLS-respecting queries.
  const verifier = createClient(url, anon);
  const { data: ures, error: uerr } =
    await verifier.auth.getUser(token);
  if (uerr || !ures.user) {
    console.log('[invite-user] getUser failed', uerr?.message,
      'token-len', token.length);
    return j({
      error: 'unauthorised',
      detail: uerr?.message ?? 'no user from token',
    }, 401);
  }
  const callerId = ures.user.id;

  const callerClient = createClient(url, anon, {
    global: { headers: { authorization: `Bearer ${token}` } },
  });
  const { data: caller, error: cerr } = await callerClient.from('users')
    .select('id, role, academy_id').eq('id', callerId).single();
  if (cerr || !caller?.academy_id) {
    console.log('[invite-user] caller lookup failed', cerr?.message,
      'callerId', callerId);
    return j({
      error: 'no academy',
      detail: cerr?.message ?? 'no users row',
    }, 403);
  }

  if (!['super_admin', 'academy_owner', 'academy_admin']
        .includes(caller.role as string)) {
    return j({ error: 'admin-or-higher required' }, 403);
  }

  // Validate any linked rows belong to caller's academy.
  const admin = createClient(url, key);
  const academyId = caller.academy_id;

  if (body.link_to_student_id) {
    const { data: s } = await admin.from('students')
      .select('id, academy_id').eq('id', body.link_to_student_id).maybeSingle();
    if (!s || s.academy_id !== academyId) {
      return j({ error: 'student not in your academy' }, 400);
    }
  }
  if (body.link_coach_id) {
    const { data: c } = await admin.from('coaches')
      .select('id, academy_id').eq('id', body.link_coach_id).maybeSingle();
    if (!c || c.academy_id !== academyId) {
      return j({ error: 'coach not in your academy' }, 400);
    }
  }
  if (body.link_student_login_id) {
    const { data: s } = await admin.from('students')
      .select('id, academy_id').eq('id', body.link_student_login_id).maybeSingle();
    if (!s || s.academy_id !== academyId) {
      return j({ error: 'student not in your academy' }, 400);
    }
  }
  if (body.center_id) {
    const { data: ce } = await admin.from('centers')
      .select('id, academy_id').eq('id', body.center_id).maybeSingle();
    if (!ce || ce.academy_id !== academyId) {
      return j({ error: 'center not in your academy' }, 400);
    }
  }

  const metadata: Record<string, string> = {
    role: body.role,
    academy_id: academyId,
    ...(body.first_name ? { first_name: body.first_name } : {}),
    ...(body.last_name ? { last_name: body.last_name } : {}),
    ...(body.center_id ? { center_id: body.center_id } : {}),
    ...(body.link_to_student_id
      ? { link_to_student_id: body.link_to_student_id } : {}),
    ...(body.link_relationship
      ? { link_relationship: body.link_relationship } : {}),
    ...(body.link_coach_id
      ? { link_coach_id: body.link_coach_id } : {}),
    ...(body.link_student_login_id
      ? { link_student_login_id: body.link_student_login_id } : {}),
  };

  const { data: invite, error: invErr } = await admin.auth.admin
    .inviteUserByEmail(body.email, {
      data: metadata,
      ...(body.redirect_to ? { redirectTo: body.redirect_to } : {}),
    });

  if (invErr) return j({ error: invErr.message }, 400);
  return j({
    ok: true,
    user_id: invite.user?.id ?? null,
    email: body.email,
    role: body.role,
  });
});

function j(b: unknown, status = 200) {
  return new Response(JSON.stringify(b),
    { status, headers: { ...corsHeaders, 'content-type': 'application/json' } });
}
