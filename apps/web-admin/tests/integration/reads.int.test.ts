import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { Fixture, HAS_ENV } from "./_helpers";

/**
 * Validates the exact READ queries the Phase 1 data layer issues
 * (src/lib/data/*), including the PostgREST embed used by listTickets, run as
 * a super-admin against seeded tenant data.
 */
describe.skipIf(!HAS_ENV)("Phase 1 read surfaces (as super-admin)", () => {
  const fx = new Fixture();
  let superEmail: string;
  let academyId: string;
  let academyNameSeen: string | null = null;

  beforeAll(async () => {
    superEmail = (await fx.createSuperAdmin()).email;
    const a = await fx.createAcademyWithOwner("read");
    academyId = a.academyId;
    await fx.createTicket(academyId, a.ownerId, "Read-path ticket");
  });

  afterAll(async () => {
    await fx.teardown();
  });

  it("listAcademies query: academy is visible with expected columns", async () => {
    const c = await fx.signIn(superEmail);
    const { data, error } = await c
      .from("academies")
      .select(
        "id, name, subscription_status, is_active, email, phone, city, state, trial_ends_at, created_at",
      )
      .eq("id", academyId)
      .single();
    expect(error).toBeNull();
    expect(data?.id).toBe(academyId);
    expect(data?.subscription_status).toBeTypeOf("string");
    academyNameSeen = data?.name ?? null;
  });

  it("listTickets query: embed resolves academy name cross-tenant", async () => {
    const c = await fx.signIn(superEmail);
    const { data, error } = await c
      .from("support_tickets")
      .select("id, subject, status, academy_id, academies(name)")
      .eq("academy_id", academyId);
    expect(error).toBeNull();
    expect((data ?? []).length).toBe(1);
    const row = data![0];
    expect(row.academies?.name).toBe(academyNameSeen);
    expect(row.status).toBe("open");
  });

  it("listPlans query: seeded plans are readable and ordered by price", async () => {
    const c = await fx.signIn(superEmail);
    const { data, error } = await c
      .from("subscription_plans")
      .select("code, monthly_price")
      .order("monthly_price", { ascending: true });
    expect(error).toBeNull();
    expect((data ?? []).length).toBeGreaterThanOrEqual(1);
    const prices = (data ?? []).map((p) => p.monthly_price);
    const sorted = [...prices].sort((a, b) => a - b);
    expect(prices).toEqual(sorted);
  });

  it("getGlobalKpi query: counts academies head-only", async () => {
    const c = await fx.signIn(superEmail);
    const { count, error } = await c
      .from("academies")
      .select("id", { count: "exact", head: true });
    expect(error).toBeNull();
    expect(count ?? 0).toBeGreaterThanOrEqual(1);
  });
});
