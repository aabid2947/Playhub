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

/** Tracks everything created so afterAll can tear it down cleanly. */
export class Fixture {
  userIds: string[] = [];
  academyIds: string[] = [];
  ticketIds: string[] = [];

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
