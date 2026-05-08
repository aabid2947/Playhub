// Public website lead form — no-auth POST endpoint.
//
// Body: {
//   academy_id: uuid,
//   first_name, last_name, email, phone, parent_name,
//   age, sport, preferred_center_id,
//   notes, source,
//   captcha_token: string  // honeypot or hCaptcha (if HCAPTCHA_SECRET set)
// }
//
// Inserts a `leads` row via service role and returns 201 with the lead id.
//
// Light spam controls for v1:
//   - honeypot field "company" must be empty (bots fill it)
//   - if HCAPTCHA_SECRET is set, validate captcha_token against hCaptcha
//   - per-IP rate limit (10/min) tracked in-memory (Edge Runtime keeps
//     the instance alive long enough for casual abuse mitigation)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';

interface Body {
  academy_id?: string;
  first_name?: string;
  last_name?: string;
  email?: string;
  phone?: string;
  parent_name?: string;
  age?: number;
  sport?: string;
  preferred_center_id?: string;
  notes?: string;
  source?: string;
  captcha_token?: string;
  company?: string;            // honeypot
}

const ALLOWED_SOURCES = new Set([
  'website', 'referral', 'walk_in', 'instagram',
  'facebook', 'google', 'event', 'other',
]);

// In-memory rate limiter (per-IP). Resets when the instance recycles.
const rateBucket = new Map<string, { count: number; reset: number }>();

function rateLimit(ip: string, limit = 10, windowMs = 60_000): boolean {
  const now = Date.now();
  const cur = rateBucket.get(ip);
  if (!cur || cur.reset < now) {
    rateBucket.set(ip, { count: 1, reset: now + windowMs });
    return true;
  }
  if (cur.count >= limit) return false;
  cur.count++;
  return true;
}

async function verifyHcaptcha(token: string): Promise<boolean> {
  const secret = Deno.env.get('HCAPTCHA_SECRET');
  if (!secret) return true;     // not configured → skip (dev mode)
  const res = await fetch('https://hcaptcha.com/siteverify', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ secret, response: token }),
  });
  if (!res.ok) return false;
  const json = await res.json() as { success: boolean };
  return !!json.success;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
    ?? 'unknown';
  if (!rateLimit(ip)) return j({ error: 'rate limited' }, 429);

  const body = await req.json().catch(() => null) as Body | null;
  if (!body) return j({ error: 'invalid json' }, 400);

  // Honeypot
  if (body.company && body.company.length > 0) {
    return j({ ok: true, id: 'spam-blocked' }, 201);   // pretend success
  }

  if (!body.academy_id) return j({ error: 'academy_id required' }, 400);
  if (!body.first_name) return j({ error: 'first_name required' }, 400);
  if (!body.email && !body.phone) {
    return j({ error: 'email or phone required' }, 400);
  }

  // Captcha (if configured)
  if (Deno.env.get('HCAPTCHA_SECRET')) {
    const ok = await verifyHcaptcha(body.captcha_token ?? '');
    if (!ok) return j({ error: 'captcha failed' }, 400);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return j({ error: 'missing env' }, 500);
  const admin = createClient(url, key);

  // Validate the academy exists + is active before inserting (prevents
  // blind academy_id stuffing).
  const { data: ac } = await admin
    .from('academies')
    .select('id, is_active')
    .eq('id', body.academy_id).maybeSingle();
  if (!ac || !ac.is_active) return j({ error: 'academy not found' }, 404);

  const source = body.source && ALLOWED_SOURCES.has(body.source)
    ? body.source : 'website';

  const { data, error } = await admin.from('leads').insert({
    academy_id: body.academy_id,
    first_name: body.first_name,
    last_name: body.last_name ?? null,
    email: body.email ?? null,
    phone: body.phone ?? null,
    parent_name: body.parent_name ?? null,
    age: body.age ?? null,
    sport: body.sport ?? null,
    preferred_center_id: body.preferred_center_id ?? null,
    notes: body.notes ?? null,
    source,
  }).select('id').single();

  if (error) return j({ error: error.message }, 400);

  // Notify owner + admins of the academy in-app.
  const { data: admins } = await admin
    .from('users')
    .select('id')
    .eq('academy_id', body.academy_id)
    .in('role', ['academy_owner', 'academy_admin']);

  if (admins && admins.length > 0) {
    await admin.from('notifications').insert(
      admins.map(a => ({
        user_id: a.id,
        academy_id: body.academy_id,
        category: 'lead',
        title: 'New lead',
        body: `${body.first_name} ${body.last_name ?? ''}`.trim()
          + (body.sport ? ` — ${body.sport}` : ''),
        deep_link: `/leads/${data.id}`,
        entity_type: 'leads',
        entity_id: data.id,
      })),
    );
  }

  return j({ ok: true, id: data.id }, 201);
});

function j(b: unknown, status = 200) {
  return new Response(JSON.stringify(b),
    { status, headers: { ...corsHeaders, 'content-type': 'application/json' } });
}
