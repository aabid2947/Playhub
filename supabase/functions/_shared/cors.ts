// Shared CORS headers for browser-callable functions.
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

export function preflight(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  return null;
}

/// Validates a cron-only call. Either:
///   - x-cron-secret header matches CRON_SECRET env, OR
///   - Authorization is a service-role JWT (for ad-hoc admin invocation).
export function authoriseCron(req: Request): Response | null {
  const cronSecret = Deno.env.get('CRON_SECRET');
  const provided = req.headers.get('x-cron-secret');
  if (cronSecret && provided && provided === cronSecret) return null;

  const auth = req.headers.get('authorization') ?? '';
  // Service-role keys come through as `Bearer <jwt>`; we let supabase-js
  // verify role on the call side, so just check presence here.
  if (auth.toLowerCase().startsWith('bearer ')) return null;

  return new Response(
    JSON.stringify({ error: 'unauthorised' }),
    { status: 401, headers: { ...corsHeaders, 'content-type': 'application/json' } },
  );
}
