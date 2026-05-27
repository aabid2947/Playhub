"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { ActionResult } from "@/lib/actions/academies";

export type PlanInput = {
  id?: string;
  code: string;
  name: string;
  description: string | null;
  monthlyPrice: number;
  yearlyPrice: number | null;
  maxStudents: number | null;
  maxCoaches: number | null;
  maxCenters: number | null;
  isActive: boolean;
};

function validate(input: PlanInput): string | null {
  if (!input.code.trim()) return "Code is required.";
  if (!input.name.trim()) return "Name is required.";
  if (!Number.isFinite(input.monthlyPrice) || input.monthlyPrice < 0)
    return "Monthly price must be a non-negative number.";
  return null;
}

export async function savePlan(input: PlanInput): Promise<ActionResult> {
  const invalid = validate(input);
  if (invalid) return { ok: false, error: invalid };

  const supabase = await createClient();
  const payload = {
    code: input.code.trim(),
    name: input.name.trim(),
    description: input.description?.trim() || null,
    monthly_price: input.monthlyPrice,
    yearly_price: input.yearlyPrice,
    max_students: input.maxStudents,
    max_coaches: input.maxCoaches,
    max_centers: input.maxCenters,
    is_active: input.isActive,
  };

  const { error } = input.id
    ? await supabase.from("subscription_plans").update(payload).eq("id", input.id)
    : await supabase.from("subscription_plans").insert(payload);
  if (error) return { ok: false, error: error.message };

  revalidatePath("/plans");
  return { ok: true };
}

export async function deletePlan(id: string): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("subscription_plans")
    .delete()
    .eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/plans");
  return { ok: true };
}
