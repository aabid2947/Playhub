// Shared Razorpay helpers: REST client + HMAC-SHA256 webhook verification.

const RAZORPAY_API = 'https://api.razorpay.com/v1';

function basicAuthHeader(): string {
  const id = Deno.env.get('RAZORPAY_KEY_ID');
  const secret = Deno.env.get('RAZORPAY_KEY_SECRET');
  if (!id || !secret) {
    throw new Error('RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET not configured');
  }
  return 'Basic ' + btoa(`${id}:${secret}`);
}

export async function createRazorpayOrder(args: {
  amount_paise: number;
  currency: string;
  receipt: string;
  notes?: Record<string, string>;
}): Promise<{ id: string; status: string; amount: number; currency: string }> {
  const res = await fetch(`${RAZORPAY_API}/orders`, {
    method: 'POST',
    headers: {
      'authorization': basicAuthHeader(),
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

export async function refundRazorpayPayment(args: {
  razorpay_payment_id: string;
  amount_paise: number;
  notes?: Record<string, string>;
}): Promise<{ id: string; status: string; amount: number }> {
  const res = await fetch(
    `${RAZORPAY_API}/payments/${args.razorpay_payment_id}/refund`,
    {
      method: 'POST',
      headers: {
        'authorization': basicAuthHeader(),
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

/// HMAC-SHA256 of the raw body using `RAZORPAY_WEBHOOK_SECRET`. Constant-time
/// compared to the `X-Razorpay-Signature` header.
export async function verifyWebhookSignature(
  rawBody: string,
  signatureHex: string,
): Promise<boolean> {
  const secret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET');
  if (!secret) throw new Error('RAZORPAY_WEBHOOK_SECRET not configured');

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
