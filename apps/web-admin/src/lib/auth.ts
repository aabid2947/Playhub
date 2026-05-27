import { createClient } from "@/lib/supabase/server";

export type CurrentUser = {
  id: string;
  email: string | null;
  name: string | null;
};

/**
 * Returns the current super-admin (the middleware has already guaranteed the
 * session is a super-admin before any page under (dashboard) renders).
 */
export async function getCurrentUser(): Promise<CurrentUser | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: row } = await supabase
    .from("users")
    .select("first_name, last_name")
    .eq("id", user.id)
    .maybeSingle();

  const name =
    [row?.first_name, row?.last_name].filter(Boolean).join(" ").trim() || null;

  return {
    id: user.id,
    email: user.email ?? null,
    name,
  };
}
