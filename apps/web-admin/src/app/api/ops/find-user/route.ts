import { NextResponse } from "next/server";
import {
  assertSuperAdmin,
  createAdminClient,
  NotSuperAdminError,
} from "@/lib/supabase/admin";

export type FoundUser = {
  id: string;
  email: string | null;
  role: string;
  academyId: string | null;
  academyName: string | null;
  lastSignInAt: string | null;
};

/**
 * Cross-tenant user lookup by email. Reaches into auth.users (last_sign_in_at)
 * via the service role — data no RLS policy exposes. Guarded by
 * assertSuperAdmin and capped at 10 matches.
 */
export async function POST(req: Request) {
  try {
    await assertSuperAdmin();
  } catch (e) {
    if (e instanceof NotSuperAdminError)
      return NextResponse.json({ ok: false, error: "Forbidden" }, { status: 403 });
    throw e;
  }

  const { email } = (await req.json().catch(() => ({}))) as { email?: string };
  if (!email || !email.trim())
    return NextResponse.json({ ok: false, error: "Email required" }, { status: 400 });

  const admin = createAdminClient();
  const { data: rows, error } = await admin
    .from("users")
    // users has two FKs to academies (academy_id, owner_id) — disambiguate.
    .select("id, email, role, academy_id, academies!users_academy_id_fkey(name)")
    .ilike("email", `%${email.trim()}%`)
    .limit(10);
  if (error)
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });

  const users: FoundUser[] = [];
  for (const r of rows ?? []) {
    const auth = await admin.auth.admin.getUserById(r.id).catch(() => null);
    users.push({
      id: r.id,
      email: r.email,
      role: r.role,
      academyId: r.academy_id,
      academyName: r.academies?.name ?? null,
      lastSignInAt: auth?.data.user?.last_sign_in_at ?? null,
    });
  }

  return NextResponse.json({ ok: true, users });
}
