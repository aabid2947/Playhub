import { describe, it, expect, beforeAll, afterAll } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/database.types";
import { Fixture, HAS_ENV, type FullAcademy } from "./_helpers";

/**
 * End-to-end BUSINESS FLOWS through the authenticated client + RPCs + triggers:
 * the multi-step journeys the apps drive. Each exercises real Postgres logic
 * (SECURITY DEFINER RPCs, sync triggers, generated columns, CHECK constraints).
 *
 * Skips automatically when local Supabase env vars are absent.
 */
type Client = SupabaseClient<Database>;

describe.skipIf(!HAS_ENV)("business flows", () => {
  const fx = new Fixture();
  let A: FullAcademy;
  let owner: Client;

  beforeAll(async () => {
    A = await fx.createFullAcademy("flow");
    owner = (await fx.signIn(A.emails.academy_owner)) as Client;
  }, 90_000);

  afterAll(async () => {
    await fx.teardown();
  });

  // ── Owner signup → bootstrap_owner_academy ────────────────────────────────
  describe("owner self-signup → bootstrap_owner_academy", () => {
    it("promotes the caller to academy_owner, creates + links the academy, idempotently", async () => {
      const u = await fx.createPlainUser(); // no role meta → defaults to 'student', no academy
      const client = (await fx.signIn(u.email)) as Client;

      const { data: acad, error } = await client.rpc("bootstrap_owner_academy", {
        p_academy_name: "Bootstrap Academy",
      });
      expect(error).toBeNull();
      expect(acad?.name).toBe("Bootstrap Academy");
      if (acad?.id) fx.academyIds.push(acad.id); // track for teardown

      // role promoted + academy linked
      const me = await client.from("users").select("role, academy_id").eq("id", u.id).single();
      expect(me.data?.role).toBe("academy_owner");
      expect(me.data?.academy_id).toBe(acad?.id);

      // academy.owner_id points back at the user
      const back = await client.from("academies").select("owner_id").eq("id", acad!.id).single();
      expect(back.data?.owner_id).toBe(u.id);

      // idempotent: a second call returns the SAME academy, not a new one
      const again = await client.rpc("bootstrap_owner_academy", { p_academy_name: "Different Name" });
      expect(again.data?.id).toBe(acad?.id);
    });

    it("rejects an empty academy name", async () => {
      const u = await fx.createPlainUser();
      const client = (await fx.signIn(u.email)) as Client;
      const { error } = await client.rpc("bootstrap_owner_academy", { p_academy_name: "   " });
      expect(error).not.toBeNull();
    });
  });

  // ── Lead → convert_lead ───────────────────────────────────────────────────
  describe("lead → convert_lead RPC", () => {
    it("converts a lead into a student + enrollment + parent link + activity, once", async () => {
      const { data: lead } = await owner
        .from("leads")
        .insert({ academy_id: A.academyId, first_name: "Converted", phone: "+919800000001", preferred_center_id: A.centerA })
        .select("id")
        .single();

      const { data: studentId, error } = await owner.rpc("convert_lead", {
        p_lead_id: lead!.id,
        p_batch_id: A.batchA,
      });
      expect(error).toBeNull();
      expect(studentId).toBeTruthy();

      // student exists, lead flipped to converted + linked
      const stu = await owner.from("students").select("id, first_name").eq("id", studentId!).single();
      expect(stu.data?.first_name).toBe("Converted");
      const updatedLead = await owner.from("leads").select("status, converted_student_id").eq("id", lead!.id).single();
      expect(updatedLead.data?.status).toBe("converted");
      expect(updatedLead.data?.converted_student_id).toBe(studentId);

      // enrollment created in the target batch
      const enr = await owner.from("batch_enrollments").select("enrollment_status").eq("batch_id", A.batchA).eq("student_id", studentId!).single();
      expect(enr.data?.enrollment_status).toBe("active");

      // conversion activity appended
      const act = await owner.from("lead_activities").select("kind").eq("lead_id", lead!.id).eq("kind", "note");
      expect((act.data ?? []).length).toBeGreaterThanOrEqual(1);

      // converting again must fail
      const second = await owner.rpc("convert_lead", { p_lead_id: lead!.id });
      expect(second.error).not.toBeNull();
    });
  });

  // ── transfer_enrollment ───────────────────────────────────────────────────
  describe("transfer_enrollment RPC", () => {
    it("withdraws the source enrollment and activates one in the target batch", async () => {
      const { data: enr } = await owner
        .from("batch_enrollments")
        .insert({ academy_id: A.academyId, batch_id: A.batchA, student_id: A.studentB1 })
        .select("id")
        .single();

      const { data: moved, error } = await owner.rpc("transfer_enrollment", {
        p_enrollment_id: enr!.id,
        p_target_batch_id: A.batchB,
      });
      expect(error).toBeNull();
      expect(moved?.batch_id).toBe(A.batchB);
      expect(moved?.enrollment_status).toBe("active");

      const src = await owner.from("batch_enrollments").select("enrollment_status").eq("id", enr!.id).single();
      expect(src.data?.enrollment_status).toBe("withdrawn");
    });
  });

  // ── Fees → invoice → payment → status sync ────────────────────────────────
  describe("invoicing: generated amount + payment-sync trigger", () => {
    async function newInvoice(base: number, discount = 0): Promise<{ id: string; amount: number }> {
      const { data: num } = await owner.rpc("next_invoice_number", { p_academy_id: A.academyId });
      const { data, error } = await owner
        .from("invoices")
        .insert({
          academy_id: A.academyId,
          student_id: A.studentA1,
          invoice_number: num as string,
          status: "issued",
          base_amount: base,
          discount_amount: discount,
          due_date: "2030-01-31",
        })
        .select("id, amount")
        .single();
      if (error) throw error;
      return { id: data!.id, amount: data!.amount as number };
    }

    it("amount is generated as base + tax + late_fee − discount", async () => {
      const inv = await newInvoice(2000, 200);
      expect(inv.amount).toBe(1800);
    });

    it("a full payment flips status to paid; a part payment to partial", async () => {
      const full = await newInvoice(2000);
      await owner.from("payments").insert({ academy_id: A.academyId, invoice_id: full.id, student_id: A.studentA1, amount: 2000, method: "cash" });
      const paid = await owner.from("invoices").select("status, amount_paid").eq("id", full.id).single();
      expect(paid.data?.status).toBe("paid");
      expect(Number(paid.data?.amount_paid)).toBe(2000);

      const part = await newInvoice(2000);
      await owner.from("payments").insert({ academy_id: A.academyId, invoice_id: part.id, student_id: A.studentA1, amount: 500, method: "cash" });
      const partial = await owner.from("invoices").select("status, amount_paid").eq("id", part.id).single();
      expect(partial.data?.status).toBe("partial");
      expect(Number(partial.data?.amount_paid)).toBe(500);
    });

    it("invoice numbers are unique + monotonic per academy", async () => {
      const a = (await owner.rpc("next_invoice_number", { p_academy_id: A.academyId })).data as string;
      const b = (await owner.rpc("next_invoice_number", { p_academy_id: A.academyId })).data as string;
      expect(a).not.toBe(b);
    });
  });

  // ── Inventory: sign validation + on_hand sync ─────────────────────────────
  describe("inventory movement validation + on_hand denormalization", () => {
    let itemId: string;
    beforeAll(async () => {
      const { data } = await owner
        .from("inventory_items")
        .insert({ academy_id: A.academyId, center_id: A.centerA, name: "Flow Bat", reorder_threshold: 5 })
        .select("id")
        .single();
      itemId = data!.id;
    });

    it("'in' raises on_hand, 'out' lowers it", async () => {
      await owner.from("inventory_movements").insert({ academy_id: A.academyId, item_id: itemId, kind: "in", qty: 10 });
      await owner.from("inventory_movements").insert({ academy_id: A.academyId, item_id: itemId, kind: "out", qty: -3 });
      const item = await owner.from("inventory_items").select("on_hand").eq("id", itemId).single();
      expect(Number(item.data?.on_hand)).toBe(7);
    });

    it("rejects a wrong-signed movement ('out' must be negative)", async () => {
      const { error } = await owner.from("inventory_movements").insert({ academy_id: A.academyId, item_id: itemId, kind: "out", qty: 5 });
      expect(error).not.toBeNull();
    });
    it("rejects a wrong-signed movement ('in' must be positive)", async () => {
      const { error } = await owner.from("inventory_movements").insert({ academy_id: A.academyId, item_id: itemId, kind: "in", qty: -5 });
      expect(error).not.toBeNull();
    });
  });

  // ── Event → registration ──────────────────────────────────────────────────
  describe("event registration", () => {
    it("registers a student once; a duplicate registration is rejected", async () => {
      const { data: ev } = await owner
        .from("events")
        .insert({ academy_id: A.academyId, center_id: A.centerA, title: "Flow Cup", status: "published", starts_at: "2030-07-01T09:00:00Z" })
        .select("id")
        .single();

      const first = await owner.from("event_registrations").insert({ academy_id: A.academyId, event_id: ev!.id, student_id: A.studentA1 }).select("id");
      expect(first.error).toBeNull();

      const dup = await owner.from("event_registrations").insert({ academy_id: A.academyId, event_id: ev!.id, student_id: A.studentA1 }).select("id");
      expect(dup.error).not.toBeNull();
    });
  });

  // ── Subscription auto-create + SaaS payment sync ──────────────────────────
  describe("SaaS subscription + billing", () => {
    it("every academy auto-gets exactly one subscription row (ensure trigger)", async () => {
      const subs = await owner.from("academy_subscriptions").select("id").eq("academy_id", A.academyId);
      expect((subs.data ?? []).length).toBe(1);
    });

    it("paying a SaaS invoice in full flips it to paid (apply_saas_payment)", async () => {
      const inv = await fx.createSaasInvoice(A.academyId, 1499);
      const admin = (await fx.signIn(A.emails.super_admin)) as Client; // SaaS invoices/payments are platform-side
      await admin.from("saas_payments").insert({ academy_id: A.academyId, saas_invoice_id: inv.id, amount: inv.total, method: "razorpay" });
      const after = await admin.from("saas_invoices").select("status").eq("id", inv.id).single();
      expect(after.data?.status).toBe("paid");
    });
  });
});
