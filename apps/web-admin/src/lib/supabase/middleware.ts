import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "@/lib/database.types";

type CookieToSet = { name: string; value: string; options: CookieOptions };

const PUBLIC_PATHS = ["/login", "/auth", "/forbidden"];

function isPublic(path: string): boolean {
  return PUBLIC_PATHS.some((p) => path === p || path.startsWith(`${p}/`));
}

/**
 * Refreshes the Supabase auth cookie AND enforces the super-admin guard on
 * every request. The guard is defence-in-depth: RLS already blocks data for
 * non-super-admins, but we never want to render the console chrome for them.
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet: CookieToSet[]) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Do not run code between createServerClient and getUser() — it keeps the
  // session fresh and avoids hard-to-debug random logouts (Supabase guidance).
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;

  // Unauthenticated → only public paths allowed.
  if (!user) {
    if (isPublic(path)) return response;
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }

  // Authenticated → confirm super-admin via the canonical RLS helper.
  const { data: isSuper } = await supabase.rpc("is_super_admin");

  if (!isSuper) {
    // Logged in but not a super-admin: bounce to /forbidden (never the app).
    if (path === "/forbidden" || path.startsWith("/auth")) return response;
    const url = request.nextUrl.clone();
    url.pathname = "/forbidden";
    return NextResponse.redirect(url);
  }

  // Super-admin landing on /login → send to the dashboard.
  if (path === "/login") {
    const url = request.nextUrl.clone();
    url.pathname = "/health";
    return NextResponse.redirect(url);
  }

  return response;
}
