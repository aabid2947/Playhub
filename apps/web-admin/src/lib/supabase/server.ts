import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/lib/database.types";

type CookieToSet = { name: string; value: string; options: CookieOptions };

/**
 * Server Supabase client (Server Components, Route Handlers, Server Actions).
 * Reads the super-admin session from cookies; all queries remain RLS-scoped.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet: CookieToSet[]) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // setAll was called from a Server Component — safe to ignore;
            // the middleware refreshes the session cookie on every request.
          }
        },
      },
    },
  );
}
