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

### 2026-06-30 — Paytm `websiteName` hardcoded (no longer a per-academy setting)
Paytm's `websiteName` is now **derived from `environment`** in the edge layer
([_shared/paytm.ts](supabase/functions/_shared/paytm.ts) `paytmWebsite()`: `stage`→`WEBSTAGING`,
`prod`→`DEFAULT`) instead of being collected from the owner. A wrong website (`DEFAULT` on staging) was
causing Paytm initiate to fail; owners shouldn't have to know the magic value. Changes: `PaytmCreds`
dropped its `website` field; `resolvePaytmCreds` no longer reads/requires `config.website` (only
`environment`); the Website-name input + display row are removed from
[payment_gateways_page.dart](apps/mobile/lib/features/payment_gateways/presentation/payment_gateways_page.dart)
and `AcademyPaymentGateway.website` getter is gone; Paytm config is now just `{environment}`. RPC relaxed
([20260630000100](supabase/migrations/20260630000100_paytm_drop_website_config.sql) — **OWED: apply**):
`set_payment_gateway` enable-check requires only `environment` for Paytm, not `website` (existing rows that
still carry `config.website` are harmless — it's ignored). Also surfaced Paytm's `resultCode` in the
initiate error for diagnosability. **Deployed this session:** `create-payment-order`. **Still NOT
redeployed (bundle their own `_shared/paytm.ts` copy; redeploy when Paytm is actually used):**
`verify-paytm-payment`, `paytm-webhook`. **GOTCHA — Paytm staging still unproven:** after the website fix,
initiate returns `resultCode 501 "System Error"` = invalid/mismatched **staging MID+merchant key** (NOT a
checksum bug — that'd be 330). Razorpay remains the proven fee path (verify-on-return + refunds built);
Paytm refunds still unbuilt. `flutter analyze` not run (standing preference).

### 2026-06-30 — eager invoice generation on fee-assign (no 24h cron lag)
A fee's current-period invoice (and its Pay button) now appears **immediately on assignment** instead of
waiting for the next daily cron. Chosen over a "compute dues on the fly / no invoice row" rewrite —
invoices stay the source of truth (GST sequential numbering, frozen tax/discount/late-fee snapshot,
payment/refund/partial linkage, overdue + `students.fee_overdue` + reporting all depend on the row).
Mechanism: [recur-invoice-generation](supabase/functions/recur-invoice-generation/index.ts) now accepts an
**optional scope** in its POST body — `{ academy_id, student_id }` or `{ academy_id, batch_id }`. No body
(the scheduled cron) = unscoped full run across all academies, unchanged. `collectStudentLevel` /
`collectBatchLevel` take a `Filter`; a `batch_id` scope skips student-level, a `student_id` scope restricts
batch-level to that student's enrolled batches and emits only them. [billing_providers.dart](apps/mobile/lib/features/billing/data/billing_providers.dart)
`assignFee` / `assignFeeToBatch` fire `_generateInvoicesNow(...)` (scoped invoke) right after the insert,
then invalidate `invoicesProvider`. **Idempotent** — the existing per-(student, fee, period_start) dedupe
means eager + scheduled can't double-bill (verified: scoped re-run on an already-billed fee → `created: 0`).
**The cron still runs daily** as the backstop + future-period generator (next month/week/quarter). The
in-app invoke is **non-fatal** (try/caught) — a failure just falls back to the cron. **Security note:**
`authoriseCron` already accepted any bearer (now the app calls it with the user's JWT + own `academy_id`);
worst case a caller triggers idempotent generation — no data exposure, nothing the cron wouldn't do.
**OWED:** `recur-invoice-generation` redeployed this session ✅; mobile needs a rebuild to ship the
assign-time trigger; `flutter analyze` not run (standing preference).

### 2026-06-30 — fee frequencies: one_time now bills + new `weekly` frequency
Two gaps in recurring-invoice generation fixed. **(1) `one_time` fees never billed** —
[recur-invoice-generation](supabase/functions/recur-invoice-generation/index.ts) used to `continue` on
`one_time`, so an assigned one-time fee produced **no invoice and no Pay button, ever** (only a manual
`createInvoice` could bill it). The cron now issues a **single** invoice for a one-time fee dated on the
assignment's **`start_date`** (`period_start = period_end = start_date`), guarded by the existing
per-(student, fee, period_start) dedupe so it can't double-bill. **(2) New `weekly` frequency** added
end-to-end: DB check constraint widened ([20260630000000](supabase/migrations/20260630000000_fee_weekly_frequency.sql)
— **OWED: apply to hosted DB**), `FeeType.weekly` in the Dart enum + form, and period math
`weeklyPeriodStart()` / `nextPeriodStart('weekly')` in [_shared/billing.ts](supabase/functions/_shared/billing.ts).
**Weekly does NOT use `billing_day`** (a day-of-month 1–28) — it anchors to rolling 7-day windows counted
from `start_date`, so the cron skips the day-of-month gate for weekly and relies on the dedupe.
**GOTCHA:** `anchorPeriodStart()` is day-of-month only — never pass it `weekly`/`one_time` (the cron
branches before calling it). **The "last 7 days" symptom was a red herring** — the dues list
([parent_providers.dart](apps/mobile/lib/features/parent/data/parent_providers.dart) `studentOutstandingDuesProvider`)
has no date filter; the "7 days" is just `due_date = period_start + 7`. **OWED before this takes effect:**
apply the migration **and redeploy `recur-invoice-generation`** (the behavior change lives in deployed edge
code); `flutter analyze` not run (standing preference); `gen:types` NOT needed (`type` is a text-check, not
a pg enum). Billing unit tests (`_shared/billing.test.ts`) pass incl. new weekly cases.

### 2026-06-30 — Razorpay verify-on-return + per-academy gateway REQUIRED for fees
**Root-caused a silent payment loss:** a student paid (Razorpay captured ₹100) but the invoice stayed
unpaid because the **webhook never fired** and there was **no fallback** — Razorpay confirmation was
webhook-only. Fix: **verify-on-return** (mirrors the Paytm flow). After the Razorpay sheet closes,
[PaymentCheckout.payInvoice](apps/mobile/lib/features/billing/data/payment_checkout.dart) now calls the
new [verify-razorpay-payment](supabase/functions/verify-razorpay-payment/index.ts) edge fn, which
re-confirms the charge **server-side via the Razorpay Payments API** ([fetchRazorpayPayment](supabase/functions/_shared/razorpay.ts))
and records it through [confirmAndRecordRazorpay](supabase/functions/_shared/razorpay_record.ts). The
**webhook stays as async backstop**; both converge on the same `payments` row via the existing UNIQUE
`razorpay_payment_id` index (no webhook refactor needed). Client "success" is never trusted alone
(invariant #6). **Fee collection now REQUIRES the academy's OWN gateway** — `create-payment-order` uses
new `resolveRazorpayCredsRequireAcademy` (**no platform fallback**; returns 422 if unconfigured). **SaaS
billing still uses the PLATFORM account** (`create-saas-order` unchanged) — two separate money paths, do
not conflate. Owner UX: a **"Set up online payments" banner** on
[fee_structures_page.dart](apps/mobile/lib/features/billing/presentation/fee_structures_page.dart) shows
until the owner enables a configured gateway (the per-academy webhook URL is shown on the existing
payment-gateways page). **GOTCHA discovered:** the app calls `create-payment-order` (unified) but only
`create-razorpay-order` (legacy) had been deployed to the hosted project — **`create-payment-order` was
missing**, so every student payment 404'd. Now deployed. **Deployed this session:** create-payment-order,
verify-razorpay-payment (JWT on), razorpay-webhook, create-saas-order. **NOT deployed (Paytm, unused):**
verify-paytm-payment, paytm-webhook. **SaaS still has no verify-on-return** (webhook + reactivate only) —
a follow-up if SaaS payments ever silently drop. Mobile needs a rebuild to ship the verify-on-return +
banner. **To collect fees, each academy must now configure Razorpay in Settings → Payment Gateways +
register its per-academy webhook** (`…/razorpay-webhook?academy=<id>`).

### 2026-06-29 — owner self-serve SaaS checkout at signup (trial vs ₹100/mo) — Phase 6
Built the deferred "Phase 6" owner self-serve SaaS payment. The academy-setup screen
([setup_academy_page.dart](apps/mobile/lib/features/dashboards/setup_academy_page.dart)) now offers
**two CTAs: "Start 14-day free trial"** (existing bootstrap path) **and "Subscribe — ₹100/month"**
(opens Razorpay). New ₹100 **`starter`** plan
([20260629000100](supabase/migrations/20260629000100_saas_self_serve_checkout.sql)). **SaaS billing uses
PlayHub's PLATFORM Razorpay keys, NOT the academy's own merchant gateway** (that's only for parents
paying the academy) — new [create-saas-order](supabase/functions/create-saas-order/index.ts) calls
`platformRazorpayCreds()`, issues/reuses a `saas_invoice`, and creates an order tagged
`notes.invoice_type='saas'`. [razorpay-webhook](supabase/functions/razorpay-webhook/index.ts) branches on
that tag → inserts `saas_payments` (idempotent via new **`saas_payments.unique_event_id`**) instead of
`payments`. **Missing trial→active conversion fixed:** `reactivate_paid_subscription()` now also converts
a paying **`trial`** sub → active (was past_due/suspended only) + rolls a fresh monthly period. Mobile:
`PaymentCheckout.paySaasSubscription()` (reuses the Razorpay sheet). **GOTCHA:** the subscribe path calls
the `bootstrap_owner_academy` RPC **directly** (not `bootstrapOwnerAcademy()`) so the `currentProfile`
invalidation is **deferred until after checkout** — otherwise RoleDashboard rebuilds and unmounts the
setup page mid-payment. A cancelled/failed payment just lands the owner on their trial (academy already
created). **OWED before prod (NOT done here):** deploy `create-saas-order` (JWT ON) + redeploy
`razorpay-webhook` (`--no-verify-jwt`); apply migration `20260629000100`; confirm the Razorpay webhook is
registered for `payment.captured` on the **platform** account (user confirmed platform keys+webhook are
configured); `flutter analyze` not run (standing preference). Self-serve plan *changes* (post-signup
upgrade in SubscriptionPage) still route through super-admin — only the signup checkout is self-serve.

### 2026-06-29 — free-trial USAGE quotas (hard, RLS-enforced; separate from soft plan caps)
A live free-trial academy (`subscription_status = 'trial'`) is now **capped on creation**: **1 sport,
2 coach records (1 head coach + 1 coach), 2 batches, 1 head_coach / 1 coach / 1 trainer login, 5 students**
(batches added [20260629000200](supabase/migrations/20260629000200_trial_quota_batches.sql)). Caps
**lift the moment it goes paid** (`active`/`past_due`); a suspended/cancelled/trial-EXPIRED academy is
already fully write-frozen by `academy_writes_allowed()`, so the quotas only bite a *valid* trial. These
are **distinct from** `subscription_plans.max_*` (those stay soft UI hints) — this is the v1.1 "real
enforcement" the soft caps deferred. Migration
[20260629000000](supabase/migrations/20260629000000_trial_quota_limits.sql): `academy_on_trial()` +
per-resource `trial_allows_*()` count helpers added as **standalone RESTRICTIVE INSERT policies** on
students, coaches, center_sports, users (+ `academy_sports` **only where that table exists** — canonical
[20260510000100](supabase/migrations/20260510000100_sports_catalog.sql) but missing on some drifted DBs,
so guarded by `to_regclass`; the **`center_sports` cap enforces "1 sport"** since the app never writes
`academy_sports`). **Why RESTRICTIVE, not editing the existing INSERT policies:** they AND on top of
whatever permissive policies exist, so this migration is **independent of the `20260627*` freeze layer**
(does NOT reference `academy_writes_allowed()`) and doesn't have to reproduce drifted policy bodies — it
applies cleanly even on a DB that never got subscription enforcement. **These trial caps ≠ the read-only
freeze:** an EXPIRED-trial "service interrupted" lockout still requires the `20260627*` migrations. **GOTCHAS for future edits:** (1) caps are **INSERT-ONLY** — never
fold a count into the shared `can_manage_*`/`can_provision_role` helpers (they gate UPDATE too → would
block *editing* existing rows at the limit); (2) every helper **excludes the new row by `id`
(`id <> p_row_id`)** because an INSERT `WITH CHECK` subquery can already see the just-inserted row
(off-by-one otherwise); (3) **staff LOGINS bypass this RLS** — invite-user creates them via service role
(auth trigger = SECURITY DEFINER), so the per-role login cap's real enforcement is in
[invite-user](supabase/functions/invite-user/index.ts) via `trial_role_quota_ok()`; the `users` RLS cap
is only a backstop. "1 sport" = 1 distinct sport across the academy (same sport re-enabled at another
center is allowed). Mobile mirror: `trialLimitsProvider` +
[trial_limits.dart](apps/mobile/lib/features/subscription/data/trial_limits.dart) greys the New-student /
New-coach / Add-sport entry points and the invite role (RLS is the hard gate); create paths invalidate
`trialLimitsProvider`. pgTAP: [rls_trial_quota.sql](supabase/tests/rls_trial_quota.sql). **OWED before
prod (NOT run here — needs local Supabase/Docker + npm):** apply the migration + run `rls_trial_quota.sql`;
web-admin `npm run gen:types` is **not** needed (no schema/column/enum change — functions + policies only);
`flutter analyze` not run (per standing preference). **Dev safety unchanged:** keep seed/demo academies
`active` so resets don't cap testers (same note as 2026-06-27).

### 2026-06-27 — subscription enforcement: a frozen academy is read-only
Academies are now **write-frozen when their subscription is frozen** — suspended/cancelled, or a
14-day trial that lapsed. Single gate `public.academy_writes_allowed()`
([20260627000200](supabase/migrations/20260627000200_subscription_enforce_writes.sql)) is AND-ed into
the write-only capability helpers + the policies that bypass them
([20260627000300](supabase/migrations/20260627000300_subscription_enforce_policies.sql)).
**GOTCHA: do NOT gate `can_admin_center_scope`** — it is reused inside the finance READ gate
`can_view_student_finance`, so gating it would block finance *reads*; gate the write-only delegators
(`can_manage_finance/invoice/batch_finance`) or the policy instead. **Stays open (carve-outs): all
reads, the SaaS pay-to-unlock path, support tickets, messaging/notifications, the parent/student event
self-register branch, and super_admin.** Recovery: a SaaS payment auto-reactivates
([20260627000100](supabase/migrations/20260627000100_saas_auto_reactivate.sql) trigger on `saas_payments`)
or super-admin clicks **Reactivate** (web-admin `reactivateSubscription`). Trial-expiry is enforced LIVE
by the helper (no cron lag); `subscription-grace-period-check` also flips lapsed trials → suspended for
UI/reporting. Mobile: a blocked owner/admin → `PaywallPage` (RoleDashboard); new
`AcademySubscription.writesAllowed/isBlocked/isTrial/trialDaysLeft/isTrialEndingSoon`; owner-shell
`_SubscriptionBanner`. Full plan + live status: [SUBSCRIPTION_ENFORCEMENT.md](SUBSCRIPTION_ENFORCEMENT.md).
**OWED before prod:** apply the four `20260627*` migrations + run
`supabase/tests/rls_subscription_enforcement.sql` (NOT run here — needs local Supabase); and **set
existing real academies to `active`/fresh-trial first, or any on an expired trial freeze on apply.**
Owner self-serve SaaS checkout (pay in-app) is a deferred fast-follow — recovery is super-admin-applied until then.

### 2026-06-19 — super-admin: per-academy Students/Coaches drill-down
Super-admin can now see each academy's **students and coaches** via a **People** sub-nav
(Students / Coaches `AppPillTabs`) on the academy detail page
([academy_detail_page.dart](apps/mobile/lib/features/super_admin/presentation/academy_detail_page.dart)
`_PeopleSection`). Backed by new `academyStudentsProvider` / `academyCoachesProvider` (family by
academyId) in [super_admin_providers.dart](apps/mobile/lib/features/super_admin/data/super_admin_providers.dart),
which **reuse the app's `Student`/`Coach` models** (cross-tenant read rides `is_super_admin` RLS);
each list is **lazy** (loads only when its tab shows). Chosen over a flat platform-wide list — it
scales (no all-students fetch) and covers coaches too. The super-admin shell stays at **4 tabs**
(Health/Academies/Plans/Tickets — no standalone Students tab).

### 2026-06-19 — Growth metrics card (client-side, NOT a materialized view)
Added an owner/admin **Growth** card at the top of the KPI dashboard
([kpi_dashboard_page.dart](apps/mobile/lib/features/analytics/presentation/kpi_dashboard_page.dart)
`_GrowthMetricsSection`): students/coaches/centers (live total vs 30 days ago) + revenue
(latest month vs prior). **Deliberate deviation from the analytics convention** — it is
computed **client-side** in [growth_metrics.dart](apps/mobile/lib/features/analytics/data/growth_metrics.dart)
(`growthMetricsProvider`) from the already-loaded `studentsProvider`/`coachesProvider`/
`centersProvider` lists + `revenueByMonthProvider`, **not** a new `analytics_*` materialized
view — so there's no migration/RLS/pgTAP/gen:types for this. Headcount growth uses the rows'
joined/created dates (`Student.enrollmentDate`, `Coach.joinDate`, and **new `Centre.createdAt`**
— added to the model's `fromMap`; the column already existed) over a rolling 30-day window;
it's approximate (a deleted row lowers the historical baseline) — fine for a directional cue,
not an audited figure. If exact period-over-period growth is ever needed, that's the point to
add a proper `analytics_growth_*` view.
**Same pass — owner home dashboard** ([home_tab.dart](apps/mobile/lib/features/home/home_tab.dart))
now surfaces four things that previously only existed deeper in the app: a **Today's overview**
card (new students today, today's revenue, classes running, overdue/pending dues), a
**Multi-center overview** grid (centers/students/coaches + lifetime **revenue** total), an
**Upcoming events** list (from `eventsListProvider`, hidden when none upcoming) and an
**Activity** feed (recent `auditLogsProvider` rows). Finance cells gate on `caps.viewRevenue`;
everything is RLS-backed. New `todaysCollectedProvider` in
[billing_providers.dart](apps/mobile/lib/features/billing/data/billing_providers.dart) sums
today's completed payments directly from `payments` (not via an analytics view, so it's live).

### 2026-06-15 — per-academy payment gateways (bring-your-own Razorpay/Paytm)
Owners can now configure their **own** Razorpay/Paytm merchant credentials; payments
in that academy route through their account (fallback to platform `Deno.env` keys when
none is enabled). **Secret handling (invariant #4):** secrets live in **Supabase Vault**,
NOT in a column; they are **write-only** — no client read path (table RLS, the
`academy_payment_gateway_status` view, or any RPC) ever returns a secret. Owners write via
the SECURITY DEFINER RPCs `set_payment_gateway` / `clear_payment_gateway` (owner-only,
own-academy); edge functions decrypt via `get_payment_gateway_credentials` (EXECUTE granted
to **service_role only**). At most one provider is `is_enabled` per academy.
([20260615000000](supabase/migrations/20260615000000_academy_payment_gateways.sql) +
[rls_payment_gateway_scope.sql](supabase/tests/rls_payment_gateway_scope.sql)).
**Edge fns now take explicit creds:** `_shared/razorpay.ts` helpers accept a `creds` arg
(no longer read `Deno.env` directly); `_shared/payment_gateway.ts` resolves academy-or-platform.
create-razorpay-order/process-refund use the invoice/payment's academy keys.
**Webhook routing:** per-academy Razorpay webhooks must use
`…/razorpay-webhook?academy=<academy_id>` (the platform URL with no param keeps using
`RAZORPAY_WEBHOOK_SECRET`); the param is a routing hint only — a wrong id fails signature
verification. Mobile: owner-only [payment_gateways](apps/mobile/lib/features/payment_gateways/)
feature + Settings entry; `Capabilities.managePaymentGateways` (owner-only). **Owed:** web-admin
`npm run gen:types` (new view/table; needs local DB — not run here).

### 2026-06-15 — Paytm charge flow built end-to-end (both gateways now wired)
Completes the deferred Paytm half. **Order creation is now provider-agnostic:**
new [create-payment-order](supabase/functions/create-payment-order/index.ts) resolves the
academy's enabled gateway (`resolveEnabledProvider`) and returns a `provider`-tagged payload;
the mobile [PaymentCheckout](apps/mobile/lib/features/billing/data/payment_checkout.dart)
dispatcher opens Razorpay (`razorpay_flutter` native sheet) **or** Paytm (hosted payment page in a
`webview_flutter` WebView — **new dep**; the official `paytm_allinonesdk` is abandoned and won't
compile on current Flutter, so we POST `mid/orderId/txnToken` to Paytm's `showPaymentPage` and detect
the callbackUrl redirect to close). The parent dues "Pay" button now calls `PaymentCheckout` (was `RazorpayCheckout`)
and passes a `BuildContext` (needed to present the Paytm WebView);
**`create-razorpay-order` + `RazorpayCheckout` are kept but superseded** by the unified path —
don't add new callers to them. Paytm crypto + APIs in
[_shared/paytm.ts](supabase/functions/_shared/paytm.ts) (proprietary checksum =
AES-128-CBC+SHA-256 with static IV `@@@@&&&&####$$$$`; merchant key MUST be 16 bytes).
**Paytm recording is authoritative-only (invariant #6):** both [paytm-webhook](supabase/functions/paytm-webhook/index.ts)
(Paytm's S2S `callbackUrl`, `?academy=<id>`) and [verify-paytm-payment](supabase/functions/verify-paytm-payment/index.ts)
(client-called after the WebView closes; caller must pass RLS on the invoice) go through one shared
[confirmAndRecordPaytm](supabase/functions/_shared/paytm_record.ts) helper that ignores the posted body,
re-confirms via the Transaction-Status API with the academy's key, and only records when a matching
`payment_attempts` row exists; idempotent via `payments.unique_event_id = 'paytm:<orderId>'`. **No platform Paytm fallback** — an academy must
bring its own; Paytm also needs `config={website,environment(stage|prod)}` (jsonb column added to
`academy_payment_gateways`; `set_payment_gateway` gained `p_config` + validates it on enable).
Schema: [20260615000100](supabase/migrations/20260615000100_paytm_payments.sql) adds `paytm` to the
`payments.method` check, `payments.paytm_order_id/paytm_txn_id`, and `payment_attempts.provider` +
nullable `razorpay_order_id` + `paytm_order_id`. **Deploy note:** `paytm-webhook` must be deployed
`--no-verify-jwt` (like `razorpay-webhook`); `create-payment-order` keeps JWT on. **Paytm refunds
are NOT built** — `process-refund` now returns 422 for `method='paytm'` (refund via Paytm dashboard)
rather than mis-recording a manual refund; building Paytm's refund API is a follow-up. **Deploy note 2:**
`verify-paytm-payment` keeps JWT on (caller-authorised). **Verified:** `flutter pub get`/`analyze`/`test`
pass (the WebView build compiles — unlike the abandoned SDK). **Still unverified (needs a real run):** the
Paytm WebView checkout on a device + the checksum against Paytm sandbox (needs sandbox creds + a test txn).

### 2026-06-14 — self-signup defaults to academy_owner (was student)
`handle_new_auth_user` now defaults an **untrusted self-signup to `academy_owner`** (no academy),
not `student` ([20260614000500](supabase/migrations/20260614000500_signup_default_owner.sql)).
Why: a self-signup is someone creating their own academy; the old `student` default left
email-confirmed signups stuck (no inline bootstrap). **Security is unchanged** — privileged fields
(academy_id/center_id/non-default role/links) are STILL honoured only from a trusted source
(app_metadata, or user_metadata when `invited_at` is set), so a self-signup gets owner **with
`academy_id = NULL`** = powerless until `bootstrap_owner_academy()` runs; the forged-academy_id
escalation stays closed. RoleDashboard routes owner+null-academy → SetupAcademyPage. pgTAP
`rls_provisioning.sql` part C updated (crafted role still dropped; safe default now owner+no-academy).
Invited parents/coaches/etc. are unaffected (their role rides the invite path).

### 2026-06-14 — Subscription removed from owner UI; in-app change-password
The **Subscription** tile was removed from owner/admin Settings (was under "Team & billing",
now "Team & support") — the SaaS plan is PlayHub/super_admin's concern, not the academy's.
`SubscriptionPage` still exists but is no longer reachable from the academy UI; per-student
billing (invoices/fees/payments) is unaffected (separate "Billing" on the home dashboard).
Also added an in-app **Change password** action on
[profile_page.dart](apps/mobile/lib/features/auth/presentation/profile_page.dart) (Account section)
via `supabase.auth.updateUser` — the forgot-password flow already covered signed-OUT users; this
covers signed-IN ones.

### 2026-06-14 — sports: academy-scoped CUSTOM sports (center_admin can create)
`sports` gained a nullable `academy_id`: NULL = global catalog (super_admin curated, seen by all),
set = that academy's private custom sport
([20260614000400](supabase/migrations/20260614000400_academy_custom_sports.sql)). The read policy
is **tightened** from `using(true)` to global + own-academy (+ super_admin) so customs don't leak
across tenants; the global `UNIQUE(code)` is relaxed to two partial unique indexes (global vs
per-academy). owner/admin/center_admin may INSERT/UPDATE **their academy's** sports only (never the
global catalog); deletes stay super_admin. Mobile: `Sport.academyId`/`isCustom`,
`SportsRepo.createCustomSport`, and the Settings → Sports "Add a sport" sheet now offers
**Create "<name>"** when the typed name isn't in the catalog (creates the custom sport + enables it
at the center). **Owed:** web-admin `npm run gen:types` (new column).

### 2026-06-14 — support tickets: center_admin can raise; owner/admin resolve
center_admin now has an in-app support channel. RLS opened `support_tickets` +
`support_ticket_messages` **INSERT** to center_admin (was owner/admin only); they already had
READ ([20260614000300](supabase/migrations/20260614000300_support_center_admin_raise.sql)).
**UPDATE stays owner/admin (+ super_admin)** — they triage and mark resolved. Mobile: center_admin
gets a **Support** entry in Settings; the academy thread page
([support_page.dart](apps/mobile/lib/features/support/presentation/support_page.dart)) now has a
**Resolve / Reopen** action visible only to owner/admin (via `SupportRepo.setStatus`, which stamps
resolved_at/closed_at). Note: the support read policy is academy-wide for owner/admin/center_admin,
so a center_admin sees all the academy's tickets (not just their own) — per-center ticket scoping
would be a separate refinement if needed.

### 2026-06-14 — support tickets: one-field raise + human ticket number
The raise flow was too heavy for non-technical academy users. The "Raise a ticket" sheet is now a
single "What's the problem?" field + an optional "This is urgent" toggle (subject derived from the
first line; staff triage category/priority). Added a sequential `support_tickets.ticket_number`
(global sequence, [20260614000200](supabase/migrations/20260614000200_support_ticket_number.sql))
surfaced via `SupportTicketRow.reference` (`#1042`) on submit + the ticket cards/thread (both the
academy [support_page.dart](apps/mobile/lib/features/support/presentation/support_page.dart) and the
super-admin views). **Owed:** web-admin `npm run gen:types` (new column).

### 2026-06-14 — inventory: per-location stock + inter-location transfers
Inventory is now **per-location**. New `inventory_stock(item_id, center_id, on_hand)` table
(`center_id IS NULL` = HO/academy pool) holds the balance of an item at each location;
`inventory_movements` gained `center_id` (location the entry affects / transfer source),
`to_center_id` (transfer dest), and a new `kind='transfer'`
([20260614000100](supabase/migrations/20260614000100_inventory_per_location_stock.sql)). The sync
trigger posts to `inventory_stock` per location: a `transfer` (qty>0) subtracts from source + adds
to dest and leaves the item total alone; the others net the location balance AND
`inventory_items.on_hand` (kept as the academy-wide **total**, so list/low-stock/reports still work).
**Balances are trigger-maintained only** — `inventory_stock` has a read policy, NO client write
policy. Convention: a catalog item meant for several centers should be HO-level
(`inventory_items.center_id IS NULL`) so all center_admins see it, with per-center qty in
inventory_stock. Mobile: `itemStockProvider`, `recordMovement` gained `centerId`/`toCenterId`,
the movement sheet has Transfer + location pickers, item page shows stock-by-location.
**Owed:** web-admin `npm run gen:types`. **Deliberately NOT done:** location-scoping the movement
INSERT (who may transfer to/from which center) — still the permissive `inv_moves_staff_insert`
(staff + academy); tenant isolation holds (academy_id), but intra-academy transfer permissions are
a follow-up that must handle the HO null-center case so admins aren't locked out.

### 2026-06-14 — inventory: UI speaks Purchase/Sale, DB stays in/out/adjustment/return
"Sale not saving" was a recognition gap, not a bug — the `out` insert path is identical to
`in` (same RLS/triggers; `recordMovement` negates the qty). The DB `kind` tokens are unchanged
(`in/out/adjustment/return`); the **UI now labels them Purchase / Sale / Return / Adjust** via
the single source of truth `kInventoryKindLabels` / `kInventoryKindHints` /
`inventoryKindLabel()` in [inventory.dart](apps/mobile/lib/features/inventory/data/inventory.dart).
Reuse those for any new inventory UI (reports, the #7 issue/return transfers) — don't hard-code
"In"/"Out" or re-map tokens per screen.

### 2026-06-14 — inventory: new items seed opening stock via a movement
Bug: created items always showed `on_hand = 0` ("0 20" in the list = 0 stock + 20
reorder) because the item form never captured opening stock. `on_hand` is
ledger-driven (the `sync_item_on_hand` trigger on `inventory_movements`) and can
NOT be set directly on `inventory_items` — so the create form now has an **Opening
stock** field that records an opening `in` movement after insert
([inventory_item_form_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_item_form_page.dart)).
**Any future stock-seeding path (CSV import, purchase/sale entry — issues #6/#7)
must do the same: write a movement, never set `on_hand`.**

### 2026-06-14 — center_admin can manage MULTIPLE centers (user_centers)
A center_admin (or any center-scoped staffer) may now be assigned to several
centers. New `user_centers(user_id, center_id)` join table = the EXTRA grants;
`users.center_id` stays the PRIMARY/home center
([20260614000000](supabase/migrations/20260614000000_user_centers_multi.sql)).
New membership helper **`current_user_in_center(center_id)`** (home center OR a
user_centers grant) replaced every inline `= current_user_center_id()` check
inside the scope helpers (`center_admin_sees_*`, `can_admin_center_scope`,
`batch_in_my_center`, `student_in_my_center`, `can_manage_batches/_batch_fields/
_student/_coach_record`, `can_provision_role`, `head_coach_sees_coach`,
`can_target_announcement`). **RLS policies were NOT touched** — they call the
helpers, so all center-scoped reads/writes/provisioning/finance span every
granted center automatically. For a user with no user_centers rows the helper is
byte-identical to the old check, so single-center roles are unaffected. **Use
`current_user_in_center(x)` (not `x = current_user_center_id()`) for any new
center gate.** Granting centers is admin-tier only (`has_admin_or_higher` —
center_admin can't self-expand). Mobile: `myCenterIdsProvider` (home + grants)
now drives the center filters (students/attendance/batches/home greeting) and the
invite sheet has an "Also manages" multi-select that writes user_centers via
`InviteRepo.grantCenters`; demo center_admin is granted Bandra in
`create_demo_users.mjs`. **Owed:** web-admin `npm run gen:types` (new table) —
needs a local DB, not run here. **Known gap:** `send-announcement` still resolves
sport-target recipients against `current_user_center_id()` (primary center only),
so a multi-center admin targeting a sport at a non-primary center passes
validation but reaches no one there until that edge fn is widened. Two mobile
**compose/config** surfaces also still use the primary center only for a
center_admin (data isolation is unaffected — these are pickers, not RLS): the
announcements composer audience ([announcement_providers.dart](apps/mobile/lib/features/announcements/data/announcement_providers.dart),
~L230/L256) and sports-settings scope ([sports_settings_page.dart](apps/mobile/lib/features/sports/presentation/sports_settings_page.dart) L46).
**Not yet built:** an edit-existing-member centers screen (invite-time assignment
+ the demo grant cover the create path; editing grants later needs UI).

### 2026-06-09 — BRAND RE-SKIN: violet → orange + navy, LIGHT-ONLY (v1, reverses 2026-06-06)
Client approved the **`ui_demo/v1` "Sports-Light"** concept, so the locked-violet
theme is **reversed**: brand is now **orange `#FF6A2C` + navy ink `#0F2540`**
(accent blue `#1763E0`), and the app ships **light only** (`main.dart`
`themeMode: ThemeMode.light`; dark theme retained but dormant). Source of truth =
[colors.ts](colors.ts) + [design_tokens.dart](apps/mobile/lib/core/design_tokens.dart)
(`AppPalette` repaletted + new `AppShadows`) + [theme.dart](apps/mobile/lib/core/theme.dart).
**Any prose saying "violet / both themes ship" is now stale** (SKILLS.md, REVAMP.md,
shared/widgets/README.md updated; older change-log entries below are historical).
New v1 shared widgets: `AppGradientHeader` (+`AppHeroStatRow`/`AppGlassChip`/`AppCircleIconButton`),
`AppFeatureCard`, `AppPillTabs`, `AppAvatar`, `AppLabeledProgress`, `AppMiniBarChart`,
`ui_helpers.dart`; upgraded `AppCard` (soft shadow), `AppStatTile` (trendUp), `AppBadge` (icon),
`AppSectionHeader` (icon/action, mixed-case). **Authoritative plan: [UI_REVAMP_V1.md](UI_REVAMP_V1.md)**;
worklist [UI_REVAMP_V1_BY_ROLE.md](UI_REVAMP_V1_BY_ROLE.md). Rollout: Phase 0 (tokens/theme/widgets)
done + **center_admin** surface in progress; other roles follow. `flutter analyze` not yet run
(standing preference — large reskin; recommend running it).

### 2026-06-08 — super-admin module completed in the app (per PLAN.md v1)
PLAN.md scopes the super-admin module to the **mobile app** (v1, line 374); the
web-admin is the **v2.0 desktop power-tool**. Completed the app's
[super_admin](apps/mobile/lib/features/super_admin/) module to match the web's
**RLS-gated** features: academy **detail** drill-down + SaaS **invoices** +
**record-payment** ([academy_detail_page.dart](apps/mobile/lib/features/super_admin/presentation/academy_detail_page.dart)),
12-month **revenue + signups charts** + open-ticket KPI on health, and ticket
**priority + assign-to-me**. New providers: `academyDetailProvider`,
`academyInvoicesProvider`, `revenueByMonthProvider`, `signupsByMonthProvider`,
`SuperAdminRepo.recordSaasPayment` / `.setTicketAssignee`; `GlobalKpi.openTickets`.
**Deliberately NOT moved (kept on web v2.0):** the **report builder/CSV export**
and the two **service-role Ops** (refresh-analytics, find-user) — the latter
can't live in the app per invariant #4 (would each need an `is_super_admin()`-gated
edge function). If asked to bring those to mobile, treat it as pulling v2.0 work
forward + building the edge functions.

### 2026-06-08 — announcement_media size limits (video uploads)
Announcement video uploads 413'd because the bucket inherited the project-wide
storage limit (local default 50 MiB). Fixes: bumped local `config.toml [storage]
file_size_limit` → 100 MiB (**hosted must raise it in Dashboard → Storage
settings — a bucket limit can't exceed the project limit**); set the
`announcement_media` bucket to 100 MiB + image/video `allowed_mime_types`
([20260608000400](supabase/migrations/20260608000400_announcement_media_limits.sql));
capped announcement video capture at **2 min** and added a client-side size
pre-check (`StorageService._ensureUnderAnnouncementLimit`) so an oversized file
fails instantly instead of uploading then 413-ing. The composer's media pick is
also now guarded (`_pickingMedia`) + try/caught — a second pick while one is open
no longer throws `already_active` as an uncaught zone error.

### 2026-06-08 — students.fee_overdue flag (unpaid indicator) + parent invoice download
**(1) Unpaid indicator.** New `students.fee_overdue boolean`
([20260608000300](supabase/migrations/20260608000300_student_fee_overdue_flag.sql)),
kept in sync by an `AFTER INSERT/UPDATE/DELETE` trigger on `invoices`
(`refresh_student_fee_overdue`, SECURITY DEFINER) — true when the student has
≥1 **overdue** invoice, false otherwise. This exists because coaching roles see
**no finance** (Phase 4) yet need to know who hasn't paid; they read this boolean
off `students` (no amounts). **It does NOT touch `students.status`** (lifecycle).
Mobile: `Student.feeOverdue`; an "Unpaid" (danger) badge shows in the batch roster
([batch_detail_page](apps/mobile/lib/features/batches/presentation/batch_detail_page.dart)),
`CoachStudentPage` header, and the shared `_StudentTile`. Decided against flipping
`status` to inactive (would clobber paused/graduated + drop students from "active"
lists). **(2) Invoice PDF download** is now offered to parents/students on the
dues rows ([parent_dashboard_tab](apps/mobile/lib/features/parent/presentation/parent_dashboard_tab.dart))
— no backend change: `generate-invoice-pdf` already runs under the caller's JWT +
RLS, and parents can read their own student's invoice.

### 2026-06-08 — coach student access scoped to their own batches (reversal)
**Reverses 20260607000700 FOR COACHES ONLY.** A coach now reads + edits only
students enrolled in batches they staff (`student_assigned_to_me`), not the whole
center, and can **no longer create** students
([20260608000200](supabase/migrations/20260608000200_coach_batch_scoped_students.sql)).
New `coach_sees_student(student_id)` helper folds into `students_academy_read`
(coach/trainer → assigned-only; other roles unchanged); `can_manage_student` drops
its coach branch (so coach INSERT is denied); `students_update` gains a coach
clause for assigned students. **head_coach + center_admin keep center-wide student
create/edit** — that part of 20260607000700 stands; only the coach rung was
tightened. Mobile mirror: new `capabilities.createStudents` (excludes coach) gates
the New-student FAB + CSV import in [students_tab.dart](apps/mobile/lib/features/students/presentation/students_tab.dart);
`manageStudents` keeps coach (their list is RLS-scoped to batch students);
`studentsProvider` no longer center-filters coach (RLS scopes by batch, and an
enrolled student may sit in another center).

### 2026-06-08 — head_coach STUDENT read scoped to their sport's batches
Narrows a head_coach's student visibility to "their sport → batch → students":
new `head_coach_sees_student(student_id)` ([20260608000500](supabase/migrations/20260608000500_head_coach_sport_scoped_students.sql))
returns true only when the student is actively enrolled in a batch that passes
`batch_in_my_center` AND `batch_in_my_sport` — folded into `students_academy_read`.
**Partially supersedes the 2026-06-07 "head_coach sees center-wide students"
behavior** (that was UI-only center filtering; read is now RLS-narrowed by sport).
WRITE (`can_manage_student`) stays center-scoped for head_coach — read is tighter
than write (same documented asymmetry as the head_coach coaches read). A student
not enrolled in any of the head_coach's batches is now invisible to them.
`studentsProvider` no longer center-filters head_coach (RLS scopes it, and an
enrolled student can carry a different `center_id` than the batch). Coach is
unchanged (own-batch students, 20260608000200).

### 2026-06-08 — head_coach coaches READ scoped to own center + own sport
Fixed: a head_coach could read **every** coach in the academy. `coaches_academy_read`
only narrowed for center_admin (`center_admin_sees_center` short-circuits true for
head_coach), so the coaches list / coach pickers showed all academy coaches to a
head_coach
([20260608000100](supabase/migrations/20260608000100_head_coach_coaches_read_scope.sql)).
New `head_coach_sees_coach(coach_id)` helper folds into the read policy: a head_coach
now sees only coaches in their own center (or null center) under one of their sports
(via `head_coach_owns_sport`), with untagged/no-`coach_sports` coaches falling back
to center scope (same NULL-sport relaxation as batches). **Read is now tighter than
write** — `can_manage_coach_record` stays center-scoped, so a head_coach can still
edit a same-center coach in another sport but can't see one (intended; reached only
via the now-scoped list). No Dart change needed — RLS narrows every read path
automatically (unlike the students case, which was client-scoped because its read
RLS was academy-wide).

### 2026-06-08 — announcements: scoped compose for coaches + photos/videos
The compose ladder opened up beyond admins
([20260608000000](supabase/migrations/20260608000000_announcement_compose_and_media.sql)):
center_admin / head_coach / coach can now post announcements, gated by the new
`can_target_announcement(roles,batches,centers,sports)` SECURITY DEFINER helper
used in the announcements insert/update `WITH CHECK` — **targeting is validated
against the composer's scope by RLS, not app code** (a coach can only name their
own batches; head_coach own-center+own-sport; center_admin own center/its
sports/its batches; non-admins may NOT target by role or leave targets empty).
New `target_sports uuid[]` + `media jsonb` columns on `announcements`; new
private `announcement_media` Storage bucket (signed URLs, `has_coach_or_higher`
to write). **Recipient model changed:** batch/sport/center targeting now resolves
to FAMILIES = enrolled students' own logins + their parents (previously batch
targeting hit the coach+parents and skipped student logins); role targeting
(admin-only) is the way to reach staff — see
[send-announcement](supabase/functions/send-announcement/index.ts), which
scopes sport resolution to the creator's center. UI: `capabilities.composeAnnouncements`
(+ `announcementEmailChannel` — coach/head_coach get push+in-app only, no email),
the composer's audience pickers adapt per role via `composerAudienceProvider`, and
the announcements page shows the compose FAB + history list to any composer.
**Web-admin `npm run gen:types` still owed** (announcements columns changed; needs
a local DB — not run here). Composer uploads media to a client-generated
announcement id BEFORE insert, so an abandoned compose can orphan bucket objects
(best-effort, same as performance_media).

### 2026-06-07 — student list scoped to own center for center_admin/head_coach
[`studentsProvider`](apps/mobile/lib/features/students/data/student_providers.dart)
now center-filters for center_admin/head_coach (own center + null-center,
mirroring `can_manage_student`) — the students *read* RLS is academy-wide, so the
list otherwise showed students they couldn't save and 42501'd on edit. This is a
**shared provider that now scopes by role** (don't assume it's academy-wide for
everyone). Also `createStudent`/`updateStudent` switched `.single()` → `.maybeSingle()`
+ a thrown `42501 PostgrestException` so an RLS block reads as "no permission"
rather than the opaque PGRST116 (same pattern as `updateBatch`). **Still open
(create side):** the student form's Center dropdown isn't restricted to the
head_coach's center, so picking another center still 42501s on save (now with a
clean message) — same residual gap as the batch form's Center dropdown.

### 2026-06-07 — head_coach batch list scoped to manageable batches
[`myBatchesProvider`](apps/mobile/lib/features/coach/data/coach_home_providers.dart)
no longer shows a head_coach **every** academy batch (the old "oversight" behavior).
It now client-filters to what RLS allows — own center (or no center) AND own sport
(or no sport), mirroring `can_manage_batch_fields` — so the coach-shell batch list /
KPIs / today / trend never offer a batch whose enrol/edit/attendance would 42501.
A head_coach with no linked `coaches` row owns zero sports → sees only sport-less
batches in their center. **Still NOT mirrored:** [batch_detail_page.dart](apps/mobile/lib/features/batches/presentation/batch_detail_page.dart)'s
`scopeOk` checks center only (not sport) — moot when reached via the now-scoped
list, but a latent over-offer if a head_coach reaches a batch by another path.

### 2026-06-07 — head_coach: own-center students + null-sport batch relaxation
Two follow-ups to the hierarchy work: **(1)** head_coach can now create/edit
STUDENT records in their own center (`can_manage_student`, 20260607000700);
`capabilities.manageStudents` includes head_coach, and the coach home has a
"Manage" section (Students / Invite staff). Students are center-scoped (not
sport-tagged), so this is center-wide for the head_coach's center. **(2)**
head_coach may manage NULL-`sport_id` batches in their center
([20260607000600](supabase/migrations/20260607000600_relax_head_coach_null_sport.sql)
relaxed `can_manage_batch_fields`/`batch_in_my_sport`: sport-tagged batches stay
sport-limited; untagged ones fall back to center scope). **UPDATE:** head_coach
creating COACH *records* is now DONE
([20260607000800](supabase/migrations/20260607000800_head_coach_manage_coaches.sql)
+ `capabilities.manageCoaches` includes head_coach) — center-scoped, completing
create-coach → assign-to-batch.

### 2026-06-07 — Org-hierarchy re-architecture started (Phase 1: provisioning ladder)
Building an explicit creation/delegation hierarchy on top of role+center scoping
(each role provisions the rung below; "higher ⊇ lower"). Phase 1 added
[`role_rank()`](supabase/migrations/20260607000000_provisioning_ladder.sql) +
`can_provision_role(target_role, center_id)` — the new vocabulary for "who may
create whom" (use these, not bare `has_admin_or_higher()`, for user provisioning).
`public.users` writes are now gated by `can_provision_role` (insert/update/delete
split; update blocks upward/lateral promotion + cross-center poaching).
invite-user enforces it server-side.

**Phase 2 done** ([20260607000200](supabase/migrations/20260607000200_head_coach_sport_scope.sql)):
head_coach is now scoped to its CENTER **and** its SPORT(s) (= the `coach_sports`
of the `coaches` row it's linked to). Batch/enrollment writes go through the new
`can_manage_batch_fields(center_id, sport_id)`; attendance/perf add `batch_in_my_sport`.
A **NULL `batches.sport_id` is NOT head_coach-manageable** — keep `sport_id` set.
`can_manage_batches(center_id)` is kept (events, not sport-bound). `center_sports`
writes moved from admin-only to `can_admin_center_scope` (center_admin enables
sports for their own center; UI mirror = `capabilities.manageSports`).

**Phase 3 done** ([20260607000300](supabase/migrations/20260607000300_batch_staff_trainer_scope.sql)):
new `batch_staff(batch_id, user_id, role)` table = trainers/assistants assigned to
a batch (primary coach still on `batches.coach_id`). `staff_on_batch(b)` = coach
or assigned staffer; `student_assigned_to_me(s)` = enrolled in a batch I staff.
Trainers now record performance **but only against a batch they staff** (a NULL
`batch_id` free-standing assessment stays denied — no scope to check); attendance
+ perf "coach"/"trainer" branches use `staff_on_batch`. Coaches can now **enrol**
into their own batch (`can_manage_enrollment` += `coach_owns_batch`).
`capabilities.recordPerformance` now includes trainer.

> Update: the `ai-insights` coach/trainer `student_assigned_to_me` gate was later
> **removed** — AI insights are visible to every role that can READ the student
> (staff academy-wide; parent/student their own). Visibility is RLS on the
> students read only. (`student_assigned_to_me` still exists, used for
> attendance/performance scope.) **UI not yet wired:** coach enrolment screen + a batch_staff
(assign-trainer) management screen — backend supports both; add when building UI.

**Phase 4 done** ([20260607000400](supabase/migrations/20260607000400_center_scoped_finance.sql)):
finance is now center-scoped. center_admin manages + reads ONLY their own
center's per-student money (fees/invoices/payments/discount + fee assignments);
parents/students see only their own student's invoices/payments; coaches/head_coaches
see no finance. Center is **derived from the row's `student_id`/`batch_id`** via
`can_manage_finance` / `can_view_student_finance` (+ `can_manage_invoice`,
`can_manage_batch_finance`, `can_view_refund`) — **no `center_id` was added to
invoices/payments**, so the recur-invoice cron / razorpay-webhook / process-refund
(service-role, RLS-bypass) are untouched and money stays idempotent+verified.
`fee_structures`/`discount_structures` gained a nullable `center_id` (NULL =
academy-wide template). **Refunds stay academy_admin+** (new
`capabilities.manageRefunds` gates the refund button; RLS write unchanged).
`capabilities.manageFinance` now includes center_admin.

**Phase 5 done** ([20260607000500](supabase/migrations/20260607000500_center_read_isolation.sql)):
finished center_admin READ isolation on the secondary lists — coaches, leads,
inventory_items, events, batch_staff now center-narrowed for center_admin (reuse
`center_admin_sees_center`/`center_admin_sees_batch`, which short-circuit for
every other role). Announcements read is now delivery-scoped (non-admins see only
announcements with a recipient row for them, or that they created; admins keep the
full view). **Messaging needed no change** — it's participant-scoped, and only
owner/academy_admin (`has_admin_or_higher`, NOT center_admin) see all threads.
**Staff reassignment needs no new code** — admin/center_admin already reassign
`batches.coach_id` (batches_update) and `users.center_id` (users_admin_update).

**Two deliberate DEFERRALS (need sign-off, NOT built):**
1. **NULL-`center_id` = visible/manageable by every center_admin** (the
   `can_admin_center_scope(null)=true` / `center_admin_sees_*(null)=true`
   convention). Tightening to "unassigned = admin-only" touches every
   center-scoped write+read policy and could lock center_admins out of rows they
   just created with no center — verify how forms populate `center_id` first.
2. **Materialized KPI/analytics views bypass RLS** (they're snapshots refreshed
   by cron), so a center_admin's dashboards may still show academy-wide
   aggregates. Row-level reads are isolated; aggregate views need a separate
   center-aware wrapper or app-side center filter.

### 2026-06-07 — SECURITY: auth trigger no longer trusts client `user_metadata`
[`handle_new_auth_user`](supabase/migrations/20260607000100_harden_auth_trigger.sql)
honours privileged fields (`role`/`academy_id`/`center_id`/links) **only** from
`raw_app_meta_data` (service-role-only) **or** from `user_metadata` when
`invited_at` is set (the GoTrue invite path). This closes a self-signup
escalation (anyone could `auth.signUp({data:{role:'academy_admin',academy_id}})`).
**Consequence:** any service-role user creation must pass privileged fields via
**`app_metadata`** (e.g. `admin.createUser({app_metadata})`), not `user_metadata` —
`create_demo_users.mjs` was updated accordingly. `inviteUserByEmail` still works
(it sets `invited_at`). Self-signups always land as `student`/no-academy and
onboard via `bootstrap_owner_academy()`.

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
