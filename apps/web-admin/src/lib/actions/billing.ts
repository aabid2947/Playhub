"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { ActionResult } from "@/lib/actions/academies";
import type { Database } from "@/lib/database.types";

type PaymentMethod = Database["public"]["Enums"]["saas_payment_method"];

/**
 * Manually record a SaaS payment against an invoice. The apply_saas_payment
 * trigger bumps amount_paid and flips the invoice to 'paid' when covered.
 * This is the platform-operator path for the deferred "self-serve plan
 * changes" — super-admin reconciles offline/Razorpay payments here.
 */
export async function recordSaasPayment(input: {
  invoiceId: string;
  academyId: string;
  amount: number;
  method: PaymentMethod;
  reference?: string | null;
}): Promise<ActionResult> {
  if (!Number.isFinite(input.amount) || input.amount <= 0) {
    return { ok: false, error: "Amount must be greater than zero." };
  }

  const supabase = await createClient();
  const { error } = await supabase.from("saas_payments").insert({
    saas_invoice_id: input.invoiceId,
    academy_id: input.academyId,
    amount: input.amount,
    method: input.method,
    reference: input.reference?.trim() || null,
    paid_at: new Date().toISOString(),
  });
  if (error) return { ok: false, error: error.message };

  revalidatePath(`/academies/${input.academyId}`);
  revalidatePath("/health");
  return { ok: true };
}
