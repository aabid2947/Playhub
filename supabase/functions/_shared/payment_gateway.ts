// Resolves which payment credentials to use for an academy: the academy's own
// configured merchant keys (Supabase Vault, via the service-role-only RPC
// `get_payment_gateway_credentials`) when enabled, else the platform-wide
// Deno.env fallback. Keeps secrets server-side — they never leave the edge
// function.

import { platformRazorpayCreds, platformWebhookSecret, type RazorpayCreds }
  from './razorpay.ts';
import type { PaytmCreds } from './paytm.ts';

// Minimal shape of the service-role supabase-js client we rely on.
interface RpcClient {
  rpc: (
    fn: string,
    args: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: { message: string } | null }>;
}

interface GatewayCredsRow {
  key_id: string | null;
  api_secret: string | null;
  webhook_secret: string | null;
  is_enabled: boolean;
  config: Record<string, unknown> | null;
}

async function fetchAcademyCreds(
  admin: RpcClient,
  academyId: string,
  provider: string,
): Promise<GatewayCredsRow | null> {
  const { data, error } = await admin.rpc('get_payment_gateway_credentials', {
    p_academy_id: academyId,
    p_provider: provider,
  });
  if (error) {
    // Don't leak credentials issues to callers; fall back to platform keys.
    console.error('get_payment_gateway_credentials failed:', error.message);
    return null;
  }
  const row = Array.isArray(data) ? data[0] : data;
  return (row as GatewayCredsRow) ?? null;
}

export interface ResolvedRazorpay extends RazorpayCreds {
  source: 'academy' | 'platform';
}

/// Razorpay key+secret for charging in this academy. Uses the academy's own
/// keys when the gateway is enabled and fully configured; otherwise platform.
export async function resolveRazorpayCreds(
  admin: RpcClient,
  academyId: string,
): Promise<ResolvedRazorpay> {
  const row = await fetchAcademyCreds(admin, academyId, 'razorpay');
  if (row?.is_enabled && row.key_id && row.api_secret) {
    return { keyId: row.key_id, keySecret: row.api_secret, source: 'academy' };
  }
  return { ...platformRazorpayCreds(), source: 'platform' };
}

/// Razorpay key+secret for an academy that MUST bring its own gateway (student
/// fee collection — money goes to the academy's account, never the platform).
/// No platform fallback: throws if the academy hasn't configured + enabled it.
export async function resolveRazorpayCredsRequireAcademy(
  admin: RpcClient,
  academyId: string,
): Promise<RazorpayCreds> {
  const row = await fetchAcademyCreds(admin, academyId, 'razorpay');
  if (!row?.is_enabled || !row.key_id || !row.api_secret) {
    throw new Error(
      'This academy has not set up its payment gateway yet. '
      + 'Ask the academy owner to configure payments in Settings.',
    );
  }
  return { keyId: row.key_id, keySecret: row.api_secret };
}

/// Razorpay webhook signing secret for verifying an inbound webhook. When an
/// `academyId` is supplied (the `?academy=` routing param) and that academy has
/// its own webhook secret, use it; otherwise the platform secret.
export async function resolveRazorpayWebhookSecret(
  admin: RpcClient,
  academyId: string | null,
): Promise<string> {
  if (academyId) {
    const row = await fetchAcademyCreds(admin, academyId, 'razorpay');
    if (row?.is_enabled && row.webhook_secret) {
      return row.webhook_secret;
    }
  }
  return platformWebhookSecret();
}

/// Which gateway an academy charges through. At most one provider is enabled;
/// 'paytm' only when it's enabled + fully configured, else 'razorpay' (which
/// covers both an enabled Razorpay merchant account and the platform fallback).
export async function resolveEnabledProvider(
  admin: RpcClient,
  academyId: string,
): Promise<'razorpay' | 'paytm'> {
  const paytm = await fetchAcademyCreds(admin, academyId, 'paytm');
  if (paytm?.is_enabled && paytm.key_id && paytm.api_secret) return 'paytm';
  return 'razorpay';
}

/// Paytm credentials for charging in this academy. There is NO platform Paytm
/// fallback — an academy must bring its own. Throws if not fully configured.
export async function resolvePaytmCreds(
  admin: RpcClient,
  academyId: string,
): Promise<PaytmCreds> {
  const row = await fetchAcademyCreds(admin, academyId, 'paytm');
  const environment = row?.config?.['environment'];
  if (
    !row?.is_enabled || !row.key_id || !row.api_secret ||
    (environment !== 'stage' && environment !== 'prod')
  ) {
    throw new Error('paytm gateway is not fully configured for this academy');
  }
  // websiteName is derived from environment in _shared/paytm.ts — not stored.
  return {
    mid: row.key_id,
    merchantKey: row.api_secret,
    environment,
  };
}
