# CLAUDE.md — working rules for PlayHub

PlayHub is a **multi-tenant sports-academy management SaaS**, India-first (INR,
Asia/Kolkata, +91). One Supabase backend serves a Flutter mobile app (the
product) and a Next.js super-admin web console.

- **What lives where:** [repo_structure.md](repo_structure.md) is the file map. Read it before hunting.
- **What's in scope / the roadmap:** [PLAN.md](PLAN.md) is authoritative for product scope, the locked stack, and version sequencing. Don't pull deferred features forward without flagging it.
- **Demo logins for manual testing:** [DEMO_CREDENTIALS.md](DEMO_CREDENTIALS.md).

The 9 roles (`user_role` enum): `super_admin`, `academy_owner`, `academy_admin`,
`center_admin`, `head_coach`, `coach`, `trainer`, `parent`, `student`.

---

## Non-negotiable invariants

These are load-bearing. Breaking one is a security/correctness bug, not a style issue.

1. **Multi-tenancy is enforced by Postgres RLS, not by app code.** Every
   tenant-scoped table has RLS keyed on `academy_id = current_user_academy_id()`
   (plus `is_super_admin()`). App-side `academy_id` filters are for *correct
   results*, never for *security*. **Every new table ships with RLS enabled in
   the same migration**, and a pgTAP test asserting cross-tenant isolation.

2. **RLS helper functions are the vocabulary.** Use the existing
   `SECURITY DEFINER` helpers in policies: `current_user_id()`,
   `current_user_role()`, `current_user_academy_id()`, `current_user_center_id()`,
   `is_super_admin()`, `has_role(...)`, `has_admin_or_higher()`. Don't re-query
   `public.users` inline inside a policy.

3. **The role-capability matrix has two mirrors that must stay in sync.** The DB
   matrix (`migrations/…_role_capabilities*.sql`) is authoritative; the Flutter
   [capabilities.dart](apps/mobile/lib/features/auth/data/capabilities.dart) is a
   client mirror used only to show/hide UI entry points. If you change one,
   change the other — and remember RLS is the real gate, so the UI must never
   offer an action RLS will reject.

4. **The service-role key never reaches a client.** It lives only in edge
   functions (`Deno.env`) and in web-admin server-only code
   ([lib/supabase/admin.ts](apps/web-admin/src/lib/supabase/admin.ts), which is
   `import "server-only"` and gated by `assertSuperAdmin()`). The mobile app gets
   only `SUPABASE_ANON_KEY`. Secrets stay in Supabase Vault / function env — never
   in [env.dart](apps/mobile/lib/core/env.dart) or any committed file.

5. **Migrations are append-only and immutable once merged.** Never edit a
   migration that has been applied; add a new timestamped one
   (`YYYYMMDDHHMMSS_description.sql`). The whole schema is reproducible from
   `migrations/` + `seed.sql`.

6. **Money paths are idempotent and verified.** Razorpay webhooks verify the
   HMAC signature and dedupe via unique constraints (e.g. `unique_event_id`).
   Don't add a payment write path that lacks signature verification + idempotency.

---

## Mobile (`apps/mobile`) — Flutter conventions

**Architecture:** feature-first. `lib/features/<name>/data/` (model + providers +
repository functions) and `.../presentation/` (pages/sheets/sections).
Cross-cutting in `lib/core/`; design system in `lib/shared/widgets/`.

- **Models are hand-written plain classes with a `fromMap(Map<String,dynamic>)`
  factory** that maps snake_case DB columns → camelCase Dart fields. **Do NOT use
  `freezed` / `json_serializable`.** Those packages are in `pubspec.yaml` but are
  *not used anywhere* — match the existing hand-written style (see
  [student.dart](apps/mobile/lib/features/students/data/student.dart)).

- **Providers are hand-written Riverpod**, not codegen. Use `Provider`,
  `FutureProvider`, `StateProvider`, `FutureProvider.family`. **Do NOT add
  `@riverpod` / `riverpod_generator` codegen** — there are zero `part '*.g.dart'`
  files and we keep it that way.

- **Data access goes through `supabaseClientProvider`.** Repository functions take
  `WidgetRef`, read the client, scope by `academyId` from
  `currentProfileProvider`, then `ref.invalidate(...)` the relevant list provider
  after a write. Pattern reference:
  [student_providers.dart](apps/mobile/lib/features/students/data/student_providers.dart).

- **Routing:** `go_router` via [router.dart](apps/mobile/lib/core/router.dart) with
  auth-aware redirects. Most navigation is role-based *shells* chosen by
  [role_dashboard.dart](apps/mobile/lib/features/dashboards/role_dashboard.dart);
  only a few entities have named deep-link routes (`/leads/:id`, `/threads/:id`).
  Add a top-level route only when you need a deep link.

- **UI:** compose from `shared/widgets` (`App*`) and `core/design_tokens.dart`
  (`AppSpacing`, `AppRadius`, `AppPalette`, …). Don't hard-code spacing/colors or
  re-implement a card/list-tile/empty-state that already exists. Status colors
  go through `AppSemanticColors.of(context)` (dark-aware), not raw `AppPalette`
  constants. Brand is **vivid violet** (`AppPalette.brandPrimary` = `#9933FF`)
  primary + a **magenta accent** (`AppPalette.brandSecondary` = `#E95FE9`), with a
  violet→magenta gradient (`AppPalette.brandGradient`) for brand marks, on neutral
  surfaces; **both light + dark ship** (the theme follows the device). (Green
  `#22C55E` is now only the semantic *success* color, not the brand —
  [colors.ts](colors.ts) / [design_tokens.dart](apps/mobile/lib/core/design_tokens.dart)
  are the locked source of truth.)
  **When building or polishing a screen, follow the playbook in
  [apps/mobile/SKILLS.md](apps/mobile/SKILLS.md).**

- **Errors:** user-facing failures route through
  [error_handler.dart](apps/mobile/lib/core/error_handler.dart) /
  [error_messages.dart](apps/mobile/lib/core/error_messages.dart). Map raw
  exceptions to friendly strings rather than surfacing them raw.

- **Config:** build-time `--dart-define` only (`SUPABASE_URL`,
  `SUPABASE_ANON_KEY`). Nothing secret.

- **Lint:** `very_good_analysis` with strict casts/inference/raw-types. Keep
  `flutter analyze` clean.

## Web-admin (`apps/web-admin`) — Next.js conventions

Super-admin-only console. Next.js 15 App Router (RSC), TypeScript, Tailwind v4,
`@supabase/ssr`. Dev port **3100**.

- **RLS-respecting by default.** Reads/writes ride on the super-admin's JWT
  through the cookie-session client
  ([lib/supabase/server.ts](apps/web-admin/src/lib/supabase/server.ts)). The
  `is_super_admin()` policies are the access control — don't reach for the service
  role to "make a query work".

- **Service role is a tiny allowlist** for operations no RLS policy can express
  (e.g. `refresh_analytics()`, touching `auth.users`). It runs only in
  `src/app/api/ops/*` route handlers, each calling `assertSuperAdmin()` first, via
  the `server-only` admin client.

- **Layering:** read logic in `src/lib/data/*` (RSC, returns camelCase row types
  mapped from snake_case); mutations in `src/lib/actions/*` (`"use server"`,
  return `ActionResult = { ok, error? }`, call `revalidatePath`). UI in
  `src/components` (primitives under `components/ui`). Don't query Supabase
  directly from a page component — go through `lib/data` / `lib/actions`.

- **Types:** regenerate with `npm run gen:types` after a schema change; consume
  `Database["public"]["Tables"|"Enums"][...]` rather than re-declaring shapes.

## Backend (`supabase`) — Postgres + edge functions

- **SQL style:** lowercase keywords, snake_case identifiers, `idx_<table>_<col>`
  indexes, `trg_<...>` triggers, policies named `<table>_<who>_<action>`. New
  table checklist: columns + `academy_id` FK → indexes → `enable row level
  security` → policies (read + write, super-admin + tenant) → `set_updated_at`
  trigger → pgTAP test.

- **Edge functions (Deno):** one folder per function with `index.ts` using
  `Deno.serve`. Reuse `_shared/` helpers (`cors.ts` for CORS + `authoriseCron`,
  `razorpay.ts`, `email.ts`, `fcm.ts`, `pdf.ts`, `billing.ts`, `schedule.ts`).
  Cron functions authorize via `authoriseCron` (`x-cron-secret` or service-role
  bearer). Put unit-testable logic in `_shared/*` with a co-located `*.test.ts`.

- Demo data: `seed.sql`; surgical reset: `wipe.sql` (preserves schema/cron/vault/
  storage/catalog) then `seed.sql` then `web-admin/scripts/create_demo_users.mjs`.

---

## Commands

```bash
# Mobile (from apps/mobile)
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

# Web-admin (from apps/web-admin)
npm run dev          # http://localhost:3100
npm run typecheck
npm run lint
npm run test         # vitest unit + integration (integration needs local Supabase)
npm run test:e2e     # playwright
npm run gen:types    # regenerate database.types.ts from local DB

# Backend (from repo root, needs Supabase CLI + Docker)
supabase start
supabase db reset    # apply migrations + seed
# pgTAP: psql "$DB_URL" -f supabase/tests/<file>.sql
```

CI runs the equivalent per surface ([.github/workflows/](.github/workflows/)),
path-filtered so each app's workflow only fires on its own changes.

---

## Working rules

- **Judge the request against scope first.** If a request conflicts with
  [PLAN.md](PLAN.md) (e.g. pulling a v1.1/v2.0 deferred item forward, adding a
  Node middle-tier, self-hosting Supabase, native instead of Flutter), or is a
  poor fit for the India-first / solo-dev / Supabase-only constraints, **lead with
  the tradeoff before implementing**, propose the better fit, then proceed as the
  user decides.

- **Match the file you're editing** — comment density, naming, and the existing
  hand-written model/provider idiom. Don't introduce a new pattern (codegen, a
  state lib, an ORM, a service layer) for one feature.

- **Schema change → ripple it through:** new/changed migration → RLS + pgTAP →
  `npm run gen:types` for web-admin → update the matching Dart `fromMap` model →
  if it's a capability, update *both* the DB matrix and `capabilities.dart`.

- **Don't commit secrets.** Anything sensitive is an env/Vault value; `.env.example`
  documents the names only.

- **Verify before claiming done:** `flutter analyze` + `flutter test` for mobile;
  `typecheck` + `lint` + `test` for web-admin; pgTAP for schema/RLS. Report
  failures with output rather than papering over them.

- **Log decisions future agents must know in the change log below.** When you make
  a change whose *consequences outlive your session* — a convention shift, a
  load-bearing decision, a renamed/moved/removed thing, a non-obvious gotcha, a
  source-of-truth that flipped, or anything that would make a future agent act on
  stale assumptions — **append a dated entry to the [Change log](#change-log--things-future-agents-must-know)
  at the bottom of this file** (newest first). Keep each entry to 1–3 lines: what
  changed, and what an agent must now do differently. This is *not* a commit log —
  don't record routine edits the code/git already explains; record only what isn't
  obvious from reading the repo. If your change makes an instruction *elsewhere* in
  this file or another doc wrong, fix that doc in the same pass (don't just log it).

---

## Change log — things future agents must know

> Newest first. See the logging rule above for what belongs here (durable
> decisions and gotchas — not routine edits). Format: `### YYYY-MM-DD — title`
> then 1–3 lines.

### 2026-06-06 — Global type scale tuned down for mobile density
The Material 3 default sizes read oversized on a dense mobile ops tool, so the type
scale in [`_textTheme()`](apps/mobile/lib/core/theme.dart) now sets explicit, smaller
`fontSize`s per role (e.g. titleLarge 22→18, headlineSmall 24→20, bodyLarge 16→15,
bodyMedium 14→13; app-bar title 17). **This is the single source of truth — screens
use `textTheme.*` roles, so size changes cascade app-wide.** Don't hard-code
`fontSize` in a screen to fight the scale; if a role feels wrong, retune it here.

### 2026-06-06 — Brand recolored green → violet (theme is locked)
The brand primary changed from green `#22C55E` to **vivid violet `#9933FF`**
(accent magenta `#E95FE9`, violet→magenta `AppPalette.brandGradient`). The locked
source of truth is [colors.ts](colors.ts) / [typography.ts](typography.ts) +
[design_tokens.dart](apps/mobile/lib/core/design_tokens.dart) +
[theme.dart](apps/mobile/lib/core/theme.dart). Green now means only semantic
*success*. **Do not restyle colors/typography** — and if you see older prose
saying "green is the brand," it's the stale wording, not a second opinion.

### 2026-06-06 — Mobile layout revamp is tracked in REVAMP.md (+ progress tracker)
[REVAMP.md](REVAMP.md) is the screen-by-screen worklist for the `apps/mobile`
layout/structure overhaul (layout & IA only — colors/type are locked, see above);
[REVAMP_PROGRESS.md](REVAMP_PROGRESS.md) is the companion checklist (every screen +
effort tier + Pending/Done status + its nested-component map). When you revamp a
mobile screen, follow REVAMP.md's process **and mark the screen done in
REVAMP_PROGRESS.md** (flip the checkbox/status + update the Progress counts).
