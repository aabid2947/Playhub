import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { randomUUID } from "node:crypto";
import { Fixture, HAS_ENV } from "./_helpers";

/**
 * Exercises the WRITE behaviour the Phase 2 server actions depend on, run as a
 * super-admin through the RLS client: academy toggle (+ audit), plan CRUD,
 * ticket update + staff reply, and manual SaaS payment (apply_saas_payment
 * trigger flips the invoice to paid).
 */
describe.skipIf(!HAS_ENV)("Phase 2 writes (as super-admin)", () => {
  const fx = new Fixture();
  let superEmail: string;
  let academyId: string;
  let ownerId: string;

  beforeAll(async () => {
    superEmail = (await fx.createSuperAdmin()).email;
    const a = await fx.createAcademyWithOwner("write");
    academyId = a.academyId;
    ownerId = a.ownerId;
  });

  afterAll(async () => {
    await fx.teardown();
  });

  it("toggles academy is_active and writes an audit_logs row", async () => {
    const c = await fx.signIn(superEmail);

    const upd = await c
      .from("academies")
      .update({ is_active: false })
      .eq("id", academyId)
      .select("is_active")
      .single();
    expect(upd.error).toBeNull();
    expect(upd.data?.is_active).toBe(false);

    const audit = await c
      .from("audit_logs")
      .select("id, action, entity_type")
      .eq("academy_id", academyId)
      .eq("entity_type", "academies");
    expect(audit.error).toBeNull();
    expect((audit.data ?? []).length).toBeGreaterThanOrEqual(1);
  });

  it("creates, updates, and deletes a subscription plan", async () => {
    const c = await fx.signIn(superEmail);
    const code = `int_${randomUUID().slice(0, 8)}`;

    const ins = await c
      .from("subscription_plans")
      .insert({ code, name: "Int Plan", monthly_price: 499 })
      .select("id")
      .single();
    expect(ins.error).toBeNull();
    const id = ins.data!.id;

    const upd = await c
      .from("subscription_plans")
      .update({ monthly_price: 599, is_active: false })
      .eq("id", id)
      .select("monthly_price, is_active")
      .single();
    expect(upd.data?.monthly_price).toBe(599);
    expect(upd.data?.is_active).toBe(false);

    const del = await c.from("subscription_plans").delete().eq("id", id).select("id");
    expect((del.data ?? []).length).toBe(1);
  });

  it("posts a staff reply and updates ticket status", async () => {
    const c = await fx.signIn(superEmail);
    const ticketId = await fx.createTicket(academyId, ownerId, "Write-path ticket");

    const reply = await c
      .from("support_ticket_messages")
      .insert({
        ticket_id: ticketId,
        academy_id: academyId,
        is_staff: true,
        body: "Looking into it.",
      })
      .select("id, is_staff")
      .single();
    expect(reply.error).toBeNull();
    expect(reply.data?.is_staff).toBe(true);

    const upd = await c
      .from("support_tickets")
      .update({ status: "in_progress" })
      .eq("id", ticketId)
      .select("status")
      .single();
    expect(upd.data?.status).toBe("in_progress");
  });

  it("records a manual SaaS payment that flips the invoice to paid", async () => {
    const c = await fx.signIn(superEmail);
    const inv = await fx.createSaasInvoice(academyId, 1000);

    const pay = await c.from("saas_payments").insert({
      saas_invoice_id: inv.id,
      academy_id: academyId,
      amount: inv.total,
      method: "manual",
      paid_at: new Date().toISOString(),
    });
    expect(pay.error).toBeNull();

    const after = await c
      .from("saas_invoices")
      .select("status, amount_paid")
      .eq("id", inv.id)
      .single();
    expect(after.data?.amount_paid).toBe(inv.total);
    expect(after.data?.status).toBe("paid");
  });
});
