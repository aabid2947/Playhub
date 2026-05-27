"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type ActionResult = { ok: true } | { ok: false; error: string };

/**
 * Enable/disable an academy platform-wide. RLS (academies_owner_write with the
 * is_super_admin() branch) is the real gate; the audit trigger records it.
 */
export async function setAcademyActive(
  id: string,
  active: boolean,
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("academies")
    .update({ is_active: active })
    .eq("id", id);
  if (error) return { ok: false, error: error.message };

  revalidatePath(`/academies/${id}`);
  revalidatePath("/academies");
  revalidatePath("/health");
  return { ok: true };
}
