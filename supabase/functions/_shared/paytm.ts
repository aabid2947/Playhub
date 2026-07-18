// Shared Paytm helpers: the proprietary checksum (AES-128-CBC + SHA-256), the
// Initiate-Transaction API (returns a txnToken for the SDK), and the
// Transaction-Status API (authoritative confirmation, used by the webhook).
//
// Credentials are passed in explicitly (per-academy, from Vault — see
// _shared/payment_gateway.ts). Nothing here reads Deno.env.
//
// Checksum reference: Paytm's official PaytmChecksum (Node) — generateSignature
// over a JSON string, AES-128-CBC with the static IV below and the merchant key
// (which must be 16 bytes for AES-128).

const PAYTM_IV = '@@@@&&&&####$$$$';
const SALT_CHARS =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

export interface PaytmCreds {
  mid: string;
  merchantKey: string;
  environment: 'stage' | 'prod';
}

function paytmHost(env: 'stage' | 'prod'): string {
  return env === 'prod'
    ? 'https://securegw.paytm.in'
    : 'https://securegw-stage.paytm.in';
}

/// The Paytm `websiteName` is fully determined by the environment — staging
/// merchants must use 'WEBSTAGING', production uses 'DEFAULT'. It's hardcoded
/// here (not a per-academy setting) so owners can't mis-enter it.
function paytmWebsite(env: 'stage' | 'prod'): string {
  return env === 'prod' ? 'DEFAULT' : 'WEBSTAGING';
}

// --- low-level crypto -------------------------------------------------------

function bytesToBase64(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function randomSalt(len = 4): string {
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  return Array.from(arr, (b) => SALT_CHARS[b % SALT_CHARS.length]).join('');
}

async function aesEncryptBase64(plaintext: string, key: string): Promise<string> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    'raw', enc.encode(key), { name: 'AES-CBC' }, false, ['encrypt'],
  );
  const ct = await crypto.subtle.encrypt(
    { name: 'AES-CBC', iv: enc.encode(PAYTM_IV) }, cryptoKey, enc.encode(plaintext),
  );
  return bytesToBase64(new Uint8Array(ct));
}

async function aesDecryptToString(b64: string, key: string): Promise<string> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    'raw', enc.encode(key), { name: 'AES-CBC' }, false, ['decrypt'],
  );
  const pt = await crypto.subtle.decrypt(
    { name: 'AES-CBC', iv: enc.encode(PAYTM_IV) }, cryptoKey, base64ToBytes(b64),
  );
  return new TextDecoder().decode(pt);
}

/// Paytm checksum over a parameter string (we always pass JSON.stringify(body)).
export async function generateChecksum(params: string, key: string): Promise<string> {
  const salt = randomSalt(4);
  const hash = (await sha256Hex(`${params}|${salt}`)) + salt;
  return aesEncryptBase64(hash, key);
}

/// Verify a Paytm checksum against a parameter string. Best-effort: the webhook
/// treats the Transaction-Status API as authoritative, so a failure here only
/// downgrades trust, it isn't the sole gate.
export async function verifyChecksum(
  params: string, key: string, checksum: string,
): Promise<boolean> {
  try {
    const decrypted = await aesDecryptToString(checksum, key);
    const salt = decrypted.slice(-4);
    const expected = (await sha256Hex(`${params}|${salt}`)) + salt;
    if (expected.length !== decrypted.length) return false;
    let mismatch = 0;
    for (let i = 0; i < expected.length; i++) {
      mismatch |= expected.charCodeAt(i) ^ decrypted.charCodeAt(i);
    }
    return mismatch === 0;
  } catch {
    return false;
  }
}

// --- APIs -------------------------------------------------------------------

/// Initiate a transaction; returns the txnToken the client SDK opens with.
export async function initiatePaytmTransaction(
  creds: PaytmCreds,
  args: {
    orderId: string;
    amount: string; // rupees as a decimal string, e.g. "500.00"
    custId: string;
    callbackUrl: string;
  },
): Promise<{ txnToken: string }> {
  const body = {
    requestType: 'Payment',
    mid: creds.mid,
    websiteName: paytmWebsite(creds.environment),
    orderId: args.orderId,
    txnAmount: { value: args.amount, currency: 'INR' },
    userInfo: { custId: args.custId },
    callbackUrl: args.callbackUrl,
  };
  const signature = await generateChecksum(JSON.stringify(body), creds.merchantKey);

  const url =
    `${paytmHost(creds.environment)}/theia/api/v1/initiateTransaction` +
    `?mid=${encodeURIComponent(creds.mid)}&orderId=${encodeURIComponent(args.orderId)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ body, head: { signature } }),
  });
  if (!res.ok) {
    throw new Error(`paytm initiate failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  const token = json?.body?.txnToken;
  if (!token) {
    const info = json?.body?.resultInfo ?? {};
    const msg = info.resultMsg ?? 'no txnToken';
    const code = info.resultCode ?? '?';
    throw new Error(`paytm initiate rejected: ${msg} (code ${code})`);
  }
  return { txnToken: token };
}

export interface PaytmStatus {
  resultStatus: string; // TXN_SUCCESS | TXN_FAILURE | PENDING | ...
  resultMsg: string;
  txnId?: string;
  txnAmount?: string;
  orderId?: string;
}

/// Authoritative server-to-server confirmation of a transaction's outcome.
export async function getPaytmTransactionStatus(
  creds: PaytmCreds,
  orderId: string,
): Promise<PaytmStatus> {
  const body = { mid: creds.mid, orderId };
  const signature = await generateChecksum(JSON.stringify(body), creds.merchantKey);

  const res = await fetch(`${paytmHost(creds.environment)}/v3/order/status`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ body, head: { signature } }),
  });
  if (!res.ok) {
    throw new Error(`paytm status failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  const b = json?.body ?? {};
  return {
    resultStatus: b?.resultInfo?.resultStatus ?? 'UNKNOWN',
    resultMsg: b?.resultInfo?.resultMsg ?? '',
    txnId: b?.txnId,
    txnAmount: b?.txnAmount,
    orderId: b?.orderId ?? orderId,
  };
}
