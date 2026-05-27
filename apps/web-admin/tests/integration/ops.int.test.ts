import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { Fixture, HAS_ENV, adminClient } from "./_helpers";

/**
 * Validates the service-role operations that back the /ops page. These run via
 * createAdminClient() in the app, each gated by assertSuperAdmin() at the
 * route layer.
 */
describe.skipIf(!HAS_ENV)("Phase 3 service-role ops", () => {
  const fx = new Fixture();
  let ownerId: string;
  let ownerEmail: string;

  beforeAll(async () => {
    const a = await fx.createAcademyWithOwner("ops");
    ownerId = a.ownerId;
    ownerEmail = a.email;
  });

  afterAll(async () => {
    await fx.teardown();
  });

  it("service role can run refresh_analytics()", async () => {
    const { error } = await adminClient().rpc("refresh_analytics");
    expect(error).toBeNull();
  });

  it("service role can read cross-tenant auth metadata (find-user path)", async () => {
    const admin = adminClient();

    // public.users lookup by email (what the route does first)
    const { data: rows, error } = await admin
      .from("users")
      .select("id, email, role, academies!users_academy_id_fkey(name)")
      .eq("id", ownerId);
    expect(error).toBeNull();
    expect((rows ?? []).length).toBe(1);
    expect(rows![0].email).toBe(ownerEmail);

    // auth.users metadata (only reachable with the service role)
    const auth = await admin.auth.admin.getUserById(ownerId);
    expect(auth.error).toBeNull();
    expect(auth.data.user?.email).toBe(ownerEmail);
  });
});
