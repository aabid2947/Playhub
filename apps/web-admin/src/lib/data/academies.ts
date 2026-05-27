import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";

export type SubscriptionStatus =
  Database["public"]["Enums"]["subscription_status"];

export type AcademyRow = {
  id: string;
  name: string;
  subscriptionStatus: SubscriptionStatus;
  isActive: boolean;
  email: string | null;
  phone: string | null;
  city: string | null;
  state: string | null;
  trialEndsAt: string | null;
  createdAt: string;
};

const SELECT =
  "id, name, subscription_status, is_active, email, phone, city, state, trial_ends_at, created_at";

function toRow(m: {
  id: string;
  name: string;
  subscription_status: SubscriptionStatus;
  is_active: boolean;
  email: string | null;
  phone: string | null;
  city: string | null;
  state: string | null;
  trial_ends_at: string | null;
  created_at: string;
}): AcademyRow {
  return {
    id: m.id,
    name: m.name,
    subscriptionStatus: m.subscription_status,
    isActive: m.is_active,
    email: m.email,
    phone: m.phone,
    city: m.city,
    state: m.state,
    trialEndsAt: m.trial_ends_at,
    createdAt: m.created_at,
  };
}

/** Every academy on the platform (super-admin RLS grants cross-tenant read). */
export async function listAcademies(): Promise<AcademyRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("academies")
    .select(SELECT)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []).map(toRow);
}

export type AcademyDetail = AcademyRow & {
  ownerId: string | null;
  ownerName: string | null;
  ownerEmail: string | null;
  memberCount: number;
  studentCount: number;
};

export async function getAcademy(id: string): Promise<AcademyDetail | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("academies")
    .select(`${SELECT}, owner_id`)
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;

  const [{ count: memberCount }, { count: studentCount }, owner] =
    await Promise.all([
      supabase
        .from("users")
        .select("id", { count: "exact", head: true })
        .eq("academy_id", id),
      supabase
        .from("students")
        .select("id", { count: "exact", head: true })
        .eq("academy_id", id),
      data.owner_id
        ? supabase
            .from("users")
            .select("first_name, last_name, email")
            .eq("id", data.owner_id)
            .maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

  const ownerRow = owner.data;
  const ownerName = ownerRow
    ? [ownerRow.first_name, ownerRow.last_name].filter(Boolean).join(" ").trim() ||
      null
    : null;

  return {
    ...toRow(data),
    ownerId: data.owner_id,
    ownerName,
    ownerEmail: ownerRow?.email ?? null,
    memberCount: memberCount ?? 0,
    studentCount: studentCount ?? 0,
  };
}
