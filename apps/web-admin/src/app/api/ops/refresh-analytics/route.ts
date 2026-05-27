import { NextResponse } from "next/server";
import {
  assertSuperAdmin,
  createAdminClient,
  NotSuperAdminError,
} from "@/lib/supabase/admin";

/**
 * refresh_analytics() is REVOKED from `authenticated`, so an RLS session can't
 * call it — only the service role can. We re-assert is_super_admin() on the
 * caller first, then run it with the service-role client.
 */
export async function POST() {
  try {
    await assertSuperAdmin();
  } catch (e) {
    if (e instanceof NotSuperAdminError)
      return NextResponse.json({ ok: false, error: "Forbidden" }, { status: 403 });
    throw e;
  }

  const admin = createAdminClient();
  const { error } = await admin.rpc("refresh_analytics");
  if (error)
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });

  return NextResponse.json({ ok: true });
}
