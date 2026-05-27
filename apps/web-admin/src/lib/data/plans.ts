import { createClient } from "@/lib/supabase/server";

export type PlanRow = {
  id: string;
  code: string;
  name: string;
  description: string | null;
  monthlyPrice: number;
  yearlyPrice: number | null;
  currency: string;
  maxStudents: number | null;
  maxCoaches: number | null;
  maxCenters: number | null;
  isActive: boolean;
};

export async function listPlans(): Promise<PlanRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("subscription_plans")
    .select("*")
    .order("monthly_price", { ascending: true });
  if (error) throw error;
  return (data ?? []).map((m) => ({
    id: m.id,
    code: m.code,
    name: m.name,
    description: m.description,
    monthlyPrice: m.monthly_price,
    yearlyPrice: m.yearly_price,
    currency: m.currency,
    maxStudents: m.max_students,
    maxCoaches: m.max_coaches,
    maxCenters: m.max_centers,
    isActive: m.is_active,
  }));
}
