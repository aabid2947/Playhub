import "server-only";

import { createClient as createServiceClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/database.types";
import { createClient as createRlsClient } from "@/lib/supabase/server";

/**
 * SERVICE-ROLE client — bypasses RLS entirely. NEVER import this from a Client
 * Component (the `server-only` guard will hard-fail the build if you try).
 *
 * Use it ONLY for the small allowlist of privileged operations that no RLS
 * policy can express (e.g. reading auth.users across tenants, impersonation,
 * forced data export). EVERY caller MUST first pass through `assertSuperAdmin`
 * so a leaked/forged session can never reach service-role power.
 */
export function createAdminClient() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY is not set — privileged operation unavailable.",
    );
  }
  return createServiceClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    key,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export class NotSuperAdminError extends Error {
  constructor() {
    super("Caller is not a platform super-admin.");
    this.name = "NotSuperAdminError";
  }
}

/**
 * Re-asserts that the CURRENT request's session belongs to a super-admin,
 * using the RLS-scoped client (so the check rides on the real JWT, not the
 * service role). Call this at the top of every privileged server action /
 * route handler before touching `createAdminClient()`.
 */
export async function assertSuperAdmin(): Promise<string> {
  const supabase = await createRlsClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new NotSuperAdminError();

  const { data: isSuper, error } = await supabase.rpc("is_super_admin");
  if (error || !isSuper) throw new NotSuperAdminError();

  return user.id;
}
