# PlayHub · Super-Admin Web Console (`@playhub/web-admin`)

A desktop web console for **PlayHub platform super-admins** (you / platform
operators), built with Next.js 15 on the same Supabase backend as the mobile
app. This is the first slice of the v2.0 "Web Admin" in [`PLAN.md`](../../PLAN.md),
scoped to the super-admin audience.

## Security model (read this first)

**RLS-respecting by default.** A super-admin signs in with Supabase Auth and
every query rides on their JWT, so the existing `is_super_admin()` policies are
the access control — the same battle-tested RLS the mobile app uses. No
service-role key is involved in normal reads/writes.

**Service role is a small allowlist.** A few operations no RLS policy can
express (e.g. `refresh_analytics()`, reaching into `auth.users`) run with the
service role inside server route handlers under [`src/app/api/ops`](src/app/api/ops).
Every one of them calls [`assertSuperAdmin()`](src/lib/supabase/admin.ts) first,
and the service-role client is `import "server-only"` so it can never reach the
browser bundle.

**Defense in depth.** [`src/middleware.ts`](src/middleware.ts) bounces
unauthenticated users to `/login` and authenticated non-super-admins to
`/forbidden`, even though RLS would already deny them data.

## Stack

Next.js 15 (App Router, RSC) · TypeScript · Tailwind v4 · `@supabase/ssr`
(cookie sessions) · TanStack Table · Recharts · Vitest · Playwright.

## Local development

Requires the repo's local Supabase running (`supabase start` from the repo
root).

```bash
cp .env.example .env.local        # fill from: supabase status -o env
npm install
npm run gen:types                 # regenerate src/lib/database.types.ts from local DB
npm run dev                       # http://localhost:3100
```

You need a super-admin account to log in. Create one against local Supabase:

```sql
-- in the local DB; then set a password via the Studio Auth UI, or use
-- supabase.auth.admin.createUser({ email, password, user_metadata:{ role:'super_admin' }})
```

## Scripts

| Script | What |
|---|---|
| `npm run dev` | Dev server on :3100 |
| `npm run build` / `start` | Production build / serve |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run lint` | ESLint |
| `npm run gen:types` | Regenerate Supabase types from local DB |
| `npm run test` | All Vitest (unit + integration) |
| `npm run test:unit` | Pure-logic unit tests (no infra) |
| `npm run test:int` | Integration tests (needs local Supabase) |
| `npm run test:e2e` | Playwright E2E (`npx playwright install chromium` once) |

## Features by phase

- **Phase 1 — read parity:** platform health KPIs + charts, academies table,
  plans, support tickets + thread.
- **Phase 2 — writes:** enable/disable academy, plan CRUD, ticket status /
  priority / assign / staff reply, manual SaaS payment reconciliation. All
  audited by existing DB triggers.
- **Phase 3 — power tools:** CSV export on every table, a cross-academy report
  builder, and the privileged ops page (`refresh_analytics`, cross-tenant user
  lookup).

## Testing

- **pgTAP** — [`../../supabase/tests/rls_super_admin.sql`](../../supabase/tests/rls_super_admin.sql)
  pins the cross-tenant RLS contract this console depends on.
- **Vitest unit** — pure helpers (`format`, `aggregate`, `csv`).
- **Vitest integration** — the real supabase-js + RLS path against local
  Supabase (seeds and tears down throwaway tenants).
- **Playwright E2E** — the auth guard, super-admin login, a privileged op, and
  non-super-admin rejection.

CI: [`.github/workflows/web-admin.yml`](../../.github/workflows/web-admin.yml).
