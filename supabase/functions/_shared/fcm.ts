// Firebase Cloud Messaging v1 API helper.
//
// Reads FCM_SERVICE_ACCOUNT (full service-account JSON, stored as a Supabase
// secret) and mints a short-lived OAuth access token, then sends a
// data+notification payload to one or many device tokens.
//
// Bulk-send strategy: FCM v1 has no real bulk endpoint; we issue per-token
// HTTPS calls in parallel, capped at 50 concurrent. For Sprint-4 fan-out
// volumes (one academy ≈ tens to hundreds of devices) this is fine.

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

let cachedToken: { value: string; expires_at: number } | null = null;

function loadServiceAccount(): ServiceAccount {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) throw new Error('FCM_SERVICE_ACCOUNT not configured');
  const parsed = JSON.parse(raw) as ServiceAccount;
  if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
    throw new Error('FCM_SERVICE_ACCOUNT missing required fields');
  }
  return parsed;
}

function pemToBinary(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function b64UrlEncode(bytes: Uint8Array | string): string {
  const s = typeof bytes === 'string'
    ? btoa(bytes)
    : btoa(String.fromCharCode(...bytes));
  return s.replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function mintAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expires_at > Date.now() + 60_000) {
    return cachedToken.value;
  }

  const sa = loadServiceAccount();
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const header = { alg: 'RS256', typ: 'JWT' };

  const headerEnc = b64UrlEncode(JSON.stringify(header));
  const claimEnc = b64UrlEncode(JSON.stringify(claim));
  const signingInput = `${headerEnc}.${claimEnc}`;

  const keyBytes = pemToBinary(sa.private_key);
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      cryptoKey,
      new TextEncoder().encode(signingInput),
    ),
  );
  const jwt = `${signingInput}.${b64UrlEncode(sig)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`FCM oauth failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json() as { access_token: string; expires_in: number };
  cachedToken = {
    value: json.access_token,
    expires_at: Date.now() + json.expires_in * 1000,
  };
  return cachedToken.value;
}

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
  deep_link?: string;
}

export interface SendResult {
  ok: number;
  failed: number;
  invalid_tokens: string[];      // unregistered/invalid — clean these up
}

const FCM_INVALID_ERRORS = new Set([
  'UNREGISTERED', 'INVALID_ARGUMENT', 'NOT_FOUND',
]);

export async function sendPush(
  tokens: string[],
  payload: PushPayload,
): Promise<SendResult> {
  if (tokens.length === 0) return { ok: 0, failed: 0, invalid_tokens: [] };

  const sa = loadServiceAccount();
  const accessToken = await mintAccessToken();
  const url
    = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  const data: Record<string, string> = {
    ...(payload.data ?? {}),
    ...(payload.deep_link ? { deep_link: payload.deep_link } : {}),
  };

  const concurrency = 50;
  const result: SendResult = { ok: 0, failed: 0, invalid_tokens: [] };

  for (let i = 0; i < tokens.length; i += concurrency) {
    const batch = tokens.slice(i, i + concurrency);
    const settled = await Promise.allSettled(batch.map(async (t) => {
      const r = await fetch(url, {
        method: 'POST',
        headers: {
          'authorization': `Bearer ${accessToken}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: t,
            notification: { title: payload.title, body: payload.body },
            data,
            android: { priority: 'HIGH' },
            apns: {
              payload: { aps: { sound: 'default', 'content-available': 1 } },
            },
          },
        }),
      });
      if (!r.ok) {
        const txt = await r.text();
        // Detect invalid-token errors so the caller can prune them.
        for (const code of FCM_INVALID_ERRORS) {
          if (txt.includes(code)) {
            return { token: t, status: 'invalid' as const };
          }
        }
        throw new Error(`fcm send failed: ${r.status} ${txt}`);
      }
      return { token: t, status: 'ok' as const };
    }));

    for (const s of settled) {
      if (s.status === 'fulfilled') {
        if (s.value.status === 'ok') result.ok++;
        else { result.failed++; result.invalid_tokens.push(s.value.token); }
      } else {
        result.failed++;
      }
    }
  }
  return result;
}
