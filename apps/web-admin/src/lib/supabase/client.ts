"use client";

import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/database.types";

/**
 * Browser Supabase client. Uses the public anon key + the logged-in
 * super-admin's cookie session, so every query is RLS-scoped by
 * is_super_admin(). No elevated privileges live in the browser.
 */
export function createClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
