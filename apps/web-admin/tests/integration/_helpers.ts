import { randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/database.types";

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
export const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
export const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

/** Integration tests need a reachable local Supabase + a service-role key. */
export const HAS_ENV = Boolean(SUPABASE_URL && ANON_KEY && SERVICE_KEY);

const PASSWORD = "Test-Passw0rd!";

export function adminClient(): SupabaseClient<Database> {
  return createClient<Database>(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function anonClient(): SupabaseClient<Database> {
  return createClient<Database>(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function uniq(tag: string) {
  // randomUUID guarantees uniqueness even across parallel vitest workers.
  return `int-${tag}-${randomUUID()}@example.invalid`;
}

export type SeededUser = { id: string; email: string };
export type SeededAcademy = {
  academyId: string;
  ownerId: string;
  email: string;
};

export type Role =
  | "super_admin"
  | "academy_owner"
  | "academy_admin"
  | "center_admin"
  | "head_coach"
  | "coach"
  | "trainer"
  | "parent"
  | "student";

/**
 * A complete single-tenant fixture for the capability-matrix tests: one academy,
 * two centers, coaches/students/batches, and one signed-in-able login per role,
 * linked exactly as production does (the handle_new_auth_user trigger reads the
 * user_metadata we pass to createUser).
 *
 *   centerA: coachA → batchA, studentA1 (also the `student`/`parent` target)
 *   centerB: coachB → batchB, studentB1
 *   `coach` login owns batchA; `trainer` login owns batchB; `head_coach` is in centerA.
 */
export type FullAcademy = {
  academyId: string;
  centerA: string;
  centerB: string;
  coachAId: string;
  coachBId: string;
  batchA: string;
  batchB: string;
  studentA1: string;
  studentB1: string;
  emails: Record<Role, string>;
};

/** Tracks everything created so afterAll can tear it down cleanly. */
export class Fixture {
  userIds: string[] = [];
  academyIds: string[] = [];
  ticketIds: string[] = [];

  /** A bare auth user (optionally with role/link metadata), tracked for teardown. */
  async createPlainUser(meta: Record<string, string> = {}): Promise<SeededUser> {
    const admin = adminClient();
    const email = uniq("plain");
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password: PASSWORD,
      email_confirm: true,
      user_metadata: meta,
    });
    if (error || !data.user) throw error ?? new Error("createUser failed");
    this.userIds.push(data.user.id);
    return { id: data.user.id, email };
  }

  async createSuperAdmin(): Promise<SeededUser> {
    const admin = adminClient();
    const email = uniq("super");
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password: PASSWORD,
      email_confirm: true,
      user_metadata: { role: "super_admin" },
    });
    if (error || !data.user) throw error ?? new Error("createUser failed");
    this.userIds.push(data.user.id);
    return { id: data.user.id, email };
  }

  async createAcademyWithOwner(tag: string): Promise<SeededAcademy> {
    const admin = adminClient();

    const { data: acad, error: e1 } = await admin
      .from("academies")
      .insert({ name: `INT ${tag} ${Date.now()}` })
      .select("id")
      .single();
    if (e1 || !acad) throw e1 ?? new Error("academy insert failed");
    this.academyIds.push(acad.id);

    const email = uniq(tag);
    const { data: u, error: e2 } = await admin.auth.admin.createUser({
      email,
      password: PASSWORD,
      email_confirm: true,
      user_metadata: { role: "academy_owner" },
    });
    if (e2 || !u.user) throw e2 ?? new Error("owner createUser failed");
    this.userIds.push(u.user.id);

    await admin.from("users").update({ academy_id: acad.id }).eq("id", u.user.id);
    await admin.from("academies").update({ owner_id: u.user.id }).eq("id", acad.id);

    return { academyId: acad.id, ownerId: u.user.id, email };
  }

  /**
   * Builds the full single-tenant fixture used by the capability matrix.
   * Entities are inserted with the service role; the 9 role logins are created
   * with metadata so the auth trigger does the coach/student/parent linking,
   * exactly like the real invite/seed path.
   */
  async createFullAcademy(tag: string): Promise<FullAcademy> {
    const admin = adminClient();

    const acad = await this.#insert("academies", { name: `INT-FULL ${tag} ${Date.now()}` });
    this.academyIds.push(acad.id);

    const cA = await this.#insert("centers", { academy_id: acad.id, name: "Center A" });
    const cB = await this.#insert("centers", { academy_id: acad.id, name: "Center B" });

    const coachA = await this.#insert("coaches", { academy_id: acad.id, center_id: cA.id, first_name: "CoachA", last_name: "X" });
    const coachB = await this.#insert("coaches", { academy_id: acad.id, center_id: cB.id, first_name: "CoachB", last_name: "Y" });
    const coachHead = await this.#insert("coaches", { academy_id: acad.id, center_id: cA.id, first_name: "Head", last_name: "Z" });

    const batchA = await this.#insert("batches", { academy_id: acad.id, center_id: cA.id, coach_id: coachA.id, name: "Batch A" });
    const batchB = await this.#insert("batches", { academy_id: acad.id, center_id: cB.id, coach_id: coachB.id, name: "Batch B" });

    const sA1 = await this.#insert("students", { academy_id: acad.id, center_id: cA.id, first_name: "StuA1", last_name: "S", parent_name: "P" });
    const sB1 = await this.#insert("students", { academy_id: acad.id, center_id: cB.id, first_name: "StuB1", last_name: "S", parent_name: "P" });

    const mk = async (role: Role, meta: Record<string, string>): Promise<string> => {
      const email = uniq(`${tag}-${role}`);
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password: PASSWORD,
        email_confirm: true,
        user_metadata: { role, ...meta },
      });
      if (error || !data.user) throw error ?? new Error(`${role} createUser failed`);
      this.userIds.push(data.user.id);
      return email;
    };

    const emails: Record<Role, string> = {
      super_admin: await mk("super_admin", {}),
      academy_owner: await mk("academy_owner", { academy_id: acad.id }),
      academy_admin: await mk("academy_admin", { academy_id: acad.id }),
      center_admin: await mk("center_admin", { academy_id: acad.id, center_id: cA.id }),
      head_coach: await mk("head_coach", { academy_id: acad.id, center_id: cA.id, link_coach_id: coachHead.id }),
      coach: await mk("coach", { academy_id: acad.id, center_id: cA.id, link_coach_id: coachA.id }),
      trainer: await mk("trainer", { academy_id: acad.id, center_id: cB.id, link_coach_id: coachB.id }),
      parent: await mk("parent", { academy_id: acad.id, link_to_student_id: sA1.id }),
      student: await mk("student", { academy_id: acad.id, center_id: cA.id, link_student_login_id: sA1.id }),
    };

    // owner_id can only be set after the owner login exists.
    const ownerId = (await adminClient().from("users").select("id").eq("email", emails.academy_owner).single()).data?.id;
    if (ownerId) await admin.from("academies").update({ owner_id: ownerId }).eq("id", acad.id);

    return {
      academyId: acad.id,
      centerA: cA.id,
      centerB: cB.id,
      coachAId: coachA.id,
      coachBId: coachB.id,
      batchA: batchA.id,
      batchB: batchB.id,
      studentA1: sA1.id,
      studentB1: sB1.id,
      emails,
    };
  }

  /** Service-role insert returning the new row's id; throws on error. */
  async #insert(table: string, row: Record<string, unknown>): Promise<{ id: string }> {
    const admin = adminClient();
    // Cast: this is a generic test helper across many tables.
    const { data, error } = await (admin.from(table as never) as any)
      .insert(row)
      .select("id")
      .single();
    if (error || !data) throw error ?? new Error(`${table} insert failed`);
    return data as { id: string };
  }

  async createTicket(
    academyId: string,
    openedBy: string,
    subject = "Integration ticket",
  ): Promise<string> {
    const admin = adminClient();
    const { data, error } = await admin
      .from("support_tickets")
      .insert({
        academy_id: academyId,
        subject,
        body: "seeded by integration test",
        priority: "normal",
        status: "open",
        opened_by: openedBy,
      })
      .select("id")
      .single();
    if (error || !data) throw error ?? new Error("ticket insert failed");
    this.ticketIds.push(data.id);
    return data.id;
  }

  /** Creates an issued SaaS invoice for an academy (uses its auto subscription). */
  async createSaasInvoice(
    academyId: string,
    amount = 1000,
  ): Promise<{ id: string; total: number }> {
    const admin = adminClient();
    const { data: sub, error: e0 } = await admin
      .from("academy_subscriptions")
      .select("id")
      .eq("academy_id", academyId)
      .single();
    if (e0 || !sub) throw e0 ?? new Error("no subscription for academy");

    const now = new Date();
    const plus = (d: number) =>
      new Date(now.getTime() + d * 86400000).toISOString();
    const { data, error } = await admin
      .from("saas_invoices")
      .insert({
        academy_id: academyId,
        subscription_id: sub.id,
        invoice_number: `INT-${randomUUID().slice(0, 8)}`,
        amount,
        tax_amount: 0,
        period_start: now.toISOString(),
        period_end: plus(30),
        due_date: plus(7),
        issued_at: now.toISOString(),
        status: "issued",
      })
      .select("id, total_amount")
      .single();
    if (error || !data) throw error ?? new Error("invoice insert failed");
    return { id: data.id, total: data.total_amount ?? amount };
  }

  /** Returns an anon client signed in as the given seeded account. */
  async signIn(email: string): Promise<SupabaseClient<Database>> {
    const client = anonClient();
    const { error } = await client.auth.signInWithPassword({
      email,
      password: PASSWORD,
    });
    if (error) throw error;
    return client;
  }

  async teardown(): Promise<void> {
    const admin = adminClient();
    for (const id of this.ticketIds) {
      await admin.from("support_tickets").delete().eq("id", id);
    }
    // Academies next — users.academy_id cascades, clearing owner rows.
    for (const id of this.academyIds) {
      await admin.from("academies").delete().eq("id", id);
    }
    for (const id of this.userIds) {
      await admin.auth.admin.deleteUser(id).catch(() => undefined);
    }
    this.ticketIds = [];
    this.academyIds = [];
    this.userIds = [];
  }
}
