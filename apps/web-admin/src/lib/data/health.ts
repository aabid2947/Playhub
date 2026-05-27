import { createClient } from "@/lib/supabase/server";
import type { SubscriptionStatus } from "@/lib/data/academies";
import {
  bucketByMonth,
  invoiceOutstanding,
  type MonthPoint,
} from "@/lib/aggregate";

export type { MonthPoint };

export type GlobalKpi = {
  academiesTotal: number;
  academiesActive: number;
  byStatus: Record<SubscriptionStatus, number>;
  platformRevenue: number; // sum of all saas_payments
  outstanding: number; // unpaid saas_invoices (issued + past_due)
  openTickets: number;
};

const EMPTY_STATUS: Record<SubscriptionStatus, number> = {
  trial: 0,
  active: 0,
  past_due: 0,
  suspended: 0,
  cancelled: 0,
};

export async function getGlobalKpi(): Promise<GlobalKpi> {
  const supabase = await createClient();

  const [academies, payments, invoices, tickets] = await Promise.all([
    supabase.from("academies").select("subscription_status, is_active"),
    supabase.from("saas_payments").select("amount"),
    supabase
      .from("saas_invoices")
      .select("total_amount, amount, amount_paid, tax_amount, status")
      .in("status", ["issued", "past_due"]),
    supabase
      .from("support_tickets")
      .select("id", { count: "exact", head: true })
      .in("status", ["open", "in_progress", "waiting_on_user"]),
  ]);

  if (academies.error) throw academies.error;
  if (payments.error) throw payments.error;
  if (invoices.error) throw invoices.error;

  const byStatus = { ...EMPTY_STATUS };
  let academiesActive = 0;
  for (const a of academies.data ?? []) {
    byStatus[a.subscription_status] = (byStatus[a.subscription_status] ?? 0) + 1;
    if (a.is_active) academiesActive += 1;
  }

  const platformRevenue = (payments.data ?? []).reduce(
    (sum, p) => sum + Number(p.amount ?? 0),
    0,
  );

  const outstanding = (invoices.data ?? []).reduce(
    (sum, i) => sum + invoiceOutstanding(i),
    0,
  );

  return {
    academiesTotal: (academies.data ?? []).length,
    academiesActive,
    byStatus,
    platformRevenue,
    outstanding,
    openTickets: tickets.count ?? 0,
  };
}

/** Platform SaaS revenue collected per month (last 12 months). */
export async function getRevenueByMonth(): Promise<MonthPoint[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("saas_payments")
    .select("amount, paid_at");
  if (error) throw error;
  return bucketByMonth(
    (data ?? []).map((p) => ({ ts: p.paid_at, amount: Number(p.amount ?? 0) })),
  );
}

/** New academy signups per month (last 12 months). */
export async function getSignupsByMonth(): Promise<MonthPoint[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("academies")
    .select("created_at");
  if (error) throw error;
  return bucketByMonth(
    (data ?? []).map((a) => ({ ts: a.created_at, amount: 1 })),
  );
}
