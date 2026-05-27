import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { Fixture, HAS_ENV } from "./_helpers";

/**
 * Exercises the SAME client path the web-admin uses (supabase-js with an
 * authenticated session) to prove the RLS contract the console depends on:
 *   - a super-admin's session can read across every tenant
 *   - an academy_owner's session is confined to their own academy
 *
 * Skips automatically when local Supabase env vars are absent.
 */
describe.skipIf(!HAS_ENV)("super-admin RLS via the client", () => {
  const fx = new Fixture();
  let superEmail: string;
  let academyA: string;
  let academyB: string;
  let ownerAEmail: string;

  beforeAll(async () => {
    const su = await fx.createSuperAdmin();
    superEmail = su.email;
    const a = await fx.createAcademyWithOwner("a");
    const b = await fx.createAcademyWithOwner("b");
    academyA = a.academyId;
    academyB = b.academyId;
    ownerAEmail = a.email;
  });

  afterAll(async () => {
    await fx.teardown();
  });

  it("super-admin: is_super_admin() is true", async () => {
    const c = await fx.signIn(superEmail);
    const { data, error } = await c.rpc("is_super_admin");
    expect(error).toBeNull();
    expect(data).toBe(true);
  });

  it("super-admin: reads both academies (cross-tenant)", async () => {
    const c = await fx.signIn(superEmail);
    const { data, error } = await c
      .from("academies")
      .select("id")
      .in("id", [academyA, academyB]);
    expect(error).toBeNull();
    expect((data ?? []).length).toBe(2);
  });

  it("academy_owner: is_super_admin() is false", async () => {
    const c = await fx.signIn(ownerAEmail);
    const { data } = await c.rpc("is_super_admin");
    expect(data).toBe(false);
  });

  it("academy_owner: sees own academy but NOT another tenant's", async () => {
    const c = await fx.signIn(ownerAEmail);

    const own = await c.from("academies").select("id").eq("id", academyA);
    expect((own.data ?? []).length).toBe(1);

    const other = await c.from("academies").select("id").eq("id", academyB);
    expect((other.data ?? []).length).toBe(0);
  });

  it("academy_owner: cannot write subscription_plans (RLS filters to 0 rows)", async () => {
    const c = await fx.signIn(ownerAEmail);
    const { data } = await c
      .from("subscription_plans")
      .update({ is_active: true })
      .eq("code", "basic")
      .select("id");
    expect((data ?? []).length).toBe(0);
  });
});
