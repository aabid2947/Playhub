// Shared Razorpay helpers: REST client + HMAC-SHA256 webhook verification.
//
// Credentials are passed in explicitly (see _shared/payment_gateway.ts) so the
// same client can charge through either a per-academy merchant account or the
// platform-wide keys. `platformRazorpayCreds()` / `platformWebhookSecret()`
// read the Deno.env fallback used when an academy hasn't configured its own.

const RAZORPAY_API = 'https://api.razorpay.com/v1';

export interface RazorpayCreds {
  keyId: string;
  keySecret: string;
}

export function platformRazorpayCreds(): RazorpayCreds {
  const keyId = Deno.env.get('RAZORPAY_KEY_ID');
  const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET');
  if (!keyId || !keySecret) {
    throw new Error('RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET not configured');
  }
  return { keyId, keySecret };
}

export function platformWebhookSecret(): string {
  const secret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET');
  if (!secret) throw new Error('RAZORPAY_WEBHOOK_SECRET not configured');
  return secret;
}

function basicAuthHeader(creds: RazorpayCreds): string {
  return 'Basic ' + btoa(`${creds.keyId}:${creds.keySecret}`);
}

export async function createRazorpayOrder(
  args: {
    amount_paise: number;
    currency: string;
    receipt: string;
    notes?: Record<string, string>;
  },
  creds: RazorpayCreds,
): Promise<{ id: string; status: string; amount: number; currency: string }> {
  const res = await fetch(`${RAZORPAY_API}/orders`, {
    method: 'POST',
    headers: {
      'authorization': basicAuthHeader(creds),
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      amount: args.amount_paise,
      currency: args.currency,
      receipt: args.receipt,
      notes: args.notes ?? {},
      payment_capture: 1,
    }),
  });
  if (!res.ok) {
    throw new Error(`razorpay order failed: ${res.status} ${await res.text()}`);
  }
  return await res.json();
}

/// Authoritative fetch of a payment by id. Used by verify-on-return to confirm
/// a charge server-side (the client-reported success is never trusted on its
/// own — invariant #6).
export async function fetchRazorpayPayment(
  paymentId: string,
  creds: RazorpayCreds,
): Promise<{
  id: string;
  status: string; // created | authorized | captured | refunded | failed
  amount: number; // paise
  currency: string;
  order_id: string | null;
}> {
  const res = await fetch(`${RAZORPAY_API}/payments/${paymentId}`, {
    headers: { authorization: basicAuthHeader(creds) },
  });
  if (!res.ok) {
    throw new Error(`razorpay fetch payment failed: ${res.status} ${await res.text()}`);
  }
  return await res.json();
}

export async function refundRazorpayPayment(
  args: {
    razorpay_payment_id: string;
    amount_paise: number;
    notes?: Record<string, string>;
  },
  creds: RazorpayCreds,
): Promise<{ id: string; status: string; amount: number }> {
  const res = await fetch(
    `${RAZORPAY_API}/payments/${args.razorpay_payment_id}/refund`,
    {
      method: 'POST',
      headers: {
        'authorization': basicAuthHeader(creds),
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        amount: args.amount_paise,
        notes: args.notes ?? {},
      }),
    },
  );
  if (!res.ok) {
    throw new Error(`razorpay refund failed: ${res.status} ${await res.text()}`);
  }
  return await res.json();
}

/// HMAC-SHA256 of the raw body using the given webhook `secret`. Constant-time
/// compared to the `X-Razorpay-Signature` header.
export async function verifyWebhookSignature(
  rawBody: string,
  signatureHex: string,
  secret: string,
): Promise<boolean> {
  if (!secret) throw new Error('razorpay webhook secret not configured');

  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(rawBody));
  const expected = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  // Constant-time compare
  if (expected.length !== signatureHex.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ signatureHex.charCodeAt(i);
  }
  return mismatch === 0;
}
