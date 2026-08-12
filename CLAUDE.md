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

### 2026-08-09 — inventory "0 20 piece": Unit is a PICKER now, quantity comes first
Diagnosed from a client screenshot ([ISSUES_2026-08-06.md](ISSUES_2026-08-06.md) #7): not a counting bug
— `inventory_items.unit` was free text pre-filled 'piece', so owners typed the QUANTITY into it (saved
unit = `"20 piece"`) and left the `0`-prefilled Opening stock alone; the list prints `qty + unit` = "0 20
piece". [inventory_item_form_page](apps/mobile/lib/features/inventory/presentation/inventory_item_form_page.dart)
now renders **quantity first** (no prefilled 0), and Unit is an `AppDropdownField` over `_kCommonUnits`
+ an "Other…" custom field whose validator **rejects digits**. The opening-stock field is also shown
**when editing an item whose `onHand == 0`** (still recorded as an `in` movement — never a direct
`on_hand` write, per the 2026-06-14 rule) so the already-broken rows can be repaired in-app; items
holding stock keep pointing at the movement sheet. Mobile-only, no migration. `flutter analyze` NOT run
(no SDK).

### 2026-08-08 — fee_structures.batch_id is now UI-reachable (batch-wise pricing)
[ISSUES_2026-08-06.md](ISSUES_2026-08-06.md) #8. `fee_structures.batch_id` existed since
[20260504000000](supabase/migrations/20260504000000_fees.sql) but was a **dead column** — never written,
shown or filtered. The fee form now has a Batch picker (`_BatchPicker`, sport-scoped + value-guarded)
that writes `batch_id` and adopts the batch's sport;
[batch_fees_section](apps/mobile/lib/features/billing/presentation/batch_fees_section.dart) passes
`prefilledBatchId` into "New fee" and its Assign sheet now offers **only `batch_id == this batch || null`**
(own first); the fee list shows the batch name in place of the sport when tagged. **Semantics: the tag
SCOPES/labels a price — it does NOT bill anyone.** Billing is still `batch_fee_assignments` /
student assignments, and the invoice cron never reads `fee_structures.batch_id` — don't "wire it up"
there without redesigning assignment. Mobile-only, no migration/RLS. `flutter analyze` NOT run (no SDK).

### 2026-08-08 — students start `pending`, auto-activate on first payment (+ student email surfaced)
Client decision ([ISSUES_2026-08-06.md](ISSUES_2026-08-06.md) #6): a new student is no longer `active` on
save. [20260808000000](supabase/migrations/20260808000000_student_pending_until_paid.sql) — **NOT yet
applied to the hosted DB** — widens the `students_status_check` to include **`pending`**, moves the column
DEFAULT `'active'` → `'pending'` (so CSV/raw-API inserts follow too), and adds
`activate_student_on_payment()` on **`payments`** (AFTER INSERT/UPDATE OF status): a `completed` payment
flips `pending` → `active` and touches **nothing else** (paused/inactive/graduated are deliberate admin
states). Covers online + manually-recorded receipts since both write `payments`. **GOTCHA: invoice
generation keys off `batch_enrollments.enrollment_status`, NOT `students.status`** — never add a
students.status filter there or a pending student can't be billed, can't pay, and can never activate.
Admins still set Active by hand (form dropdown, now listing Pending first). Mobile mirror: form default +
`_StatusBadge` (pending = warning) + list status filter. Same pass, #5: the student's own `email` column
had **no edit-mode surface** (only `parent_email` showed) — added a "Student email" field, and the
parent/student dashboard hero now shows student-email-else-parent-email.
pgTAP [student_pending_activation.sql](supabase/tests/student_pending_activation.sql) written, **not run**
(no local Supabase). `gen:types` NOT needed (text column, check-only). `flutter analyze` NOT run (no SDK).

### 2026-08-06 — payments: connectivity failures are now retryable, never a dead-end snackbar
Client ask ([ISSUES_2026-08-06.md](ISSUES_2026-08-06.md) #2). `CheckoutFailure` gained **`isNetwork`**
([razorpay_checkout.dart](apps/mobile/lib/features/billing/data/razorpay_checkout.dart), + shared
`looksLikeNetworkError(String)`), set ONLY where no charge can have happened — order creation
(`create-payment-order` / `create-saas-order`) and a Razorpay-sheet error whose message reads as
connectivity. **Deliberately NOT set on a verify failure** (`verify-*-payment`): the money may already
have moved, so those keep "payment is being confirmed…" and let the webhook reconcile — do not "fix"
that into a retry. All four checkout call sites (subscription page, setup/signup, parent dues, fee-lock)
now loop on a shared [payment_offline_dialog.dart](apps/mobile/lib/features/billing/presentation/payment_offline_dialog.dart)
("No internet connection · you haven't been charged" → Try again / Close). Signup extra: bootstrap is
tracked by `academyCreated`, and on a failed bootstrap the `finally` **no longer invalidates
`currentProfileProvider`** (re-fetching over the dead connection replaced the retry message with an
error page). Mobile-only. `flutter analyze` NOT run — Flutter SDK is absent on this machine.

### 2026-08-06 — REVERSES "Subscription removed from owner UI": plans are owner-facing again
Client decision (SANGEETA SYSTEMS review, [ISSUES_2026-08-06.md](ISSUES_2026-08-06.md) #1/#3/#4) —
**supersedes the 2026-06-14 entry that pulled Subscription out of Settings.** Three surfaces now expose
the SaaS plan to the owner: (1) a **"Plans & subscription"** tile is back in Settings → *Team & billing*
([settings_tab.dart](apps/mobile/lib/features/settings/settings_tab.dart)), gated on
`caps.manageSubscription` (owner-only, so admins don't reach a checkout they can't complete); (2) the
owner-shell trial strip + a new `_TrialUpgradeCard` at the top of
[home_tab.dart](apps/mobile/lib/features/home/home_tab.dart) show for the **WHOLE trial**, not just
`isTrialEndingSoon` (which now only picks the amber/urgent styling); (3)
[setup_academy_page.dart](apps/mobile/lib/features/dashboards/setup_academy_page.dart) replaced its two
hardcoded buttons (trial / "₹100 starter") with a **radio list of every active plan from
`availablePlansProvider` plus the free trial**, passing the chosen `plan_code` into
`paySaasSubscription` — so adding/repricing a plan in `subscription_plans` now changes the signup screen
with no code edit. Mobile-only, no migration/RLS/deploy. **Don't re-hide Subscription from Settings.**
`flutter analyze` NOT run — Flutter is not installed on this machine (not a preference; the SDK is absent).

### 2026-07-29 — email.ts: deliverability headers + CRLF-injection & lone-dot fixes (still Gmail SMTP)
Owner decision: **stay on Gmail SMTP, no new provider.** [_shared/email.ts](supabase/functions/_shared/email.ts)
now emits `Date`, `Message-ID`, `Reply-To` (+ optional `List-Unsubscribe` via a new `unsubscribe_url` field) and
sends HTML as **multipart/alternative** with a plaintext part — the previous header set (From/To/Subject/MIME/
Content-Type only) was missing signals receivers weight heavily. Subjects are **RFC 2047** encoded when non-ASCII
(Hindi/Marathi names were going out as raw UTF-8, which is invalid). **Two bugs fixed in passing:** every
caller-supplied header value now goes through `headerSafe()` — announcement subjects are user-composed, so a CRLF
could **inject a `Bcc:`** — and bodies are **base64** with 76-char wrapping, which kills both the 998-octet line
limit and the lone-`.` line that would end SMTP DATA early (base64 has no "."). Pure helpers are exported +
covered by [email.test.ts](supabase/functions/_shared/email.test.ts) (runs in CI: `deno test _shared/`; `email.ts`
added to the `deno check` list). **NOT fixed — the dominant spam cause is DNS, not code:** SPF/DKIM authenticate
the Gmail account's domain while `From:` claims `SMTP_FROM`'s, so **DMARC never aligns** until Workspace DKIM +
`include:_spf.google.com` are published for the SMTP_FROM domain. **OWED: redeploy `send-announcement`** (the only
`sendEmail` caller) — it bundles its own copy of `_shared/`. Deno not installed locally; helper logic was
validated in Node (17 assertions), `deno test` itself not run here.

### 2026-07-29 — package/bundle id renamed `ai.hammad.playhub` → `ai.playhub`
Renamed everywhere: Android `namespace`/`applicationId`, manifest deep-link `android:scheme`, Kotlin package +
its directory (`kotlin/ai/playhub/`), iOS `PRODUCT_BUNDLE_IDENTIFIER` (+ `.RunnerTests`) and `CFBundleURLTypes`,
and the **two hardcoded Dart deep links** (`invite_repo.sendPasswordReset`, `forgot_password_page`) — those are the
ones that silently break invites/resets if they drift from the manifest, so keep all four scheme sites in sync.
**Edge functions reference no package name** (`invite-user` only forwards a caller-supplied `redirect_to`) — no
redeploy needed. Android `google-services.json` was replaced with a freshly downloaded one; note it points at a
**NEW Firebase project `playhub-live`** (was `playhub-348c7`), not just a new app in the old project.
**CRITICAL/OWED — replace the `FCM_SERVICE_ACCOUNT` Supabase secret with a service account from `playhub-live`**:
[_shared/fcm.ts](supabase/functions/_shared/fcm.ts) sends to `/v1/projects/${sa.project_id}/messages:send`, so
while that secret holds the old project's key, every push fails (FCM tokens are project-scoped). Secret-only —
no code change or redeploy. **STILL STALE: `ios/Runner/GoogleService-Info.plist`** (`ai.hammad.playhub`,
old project) — register an iOS app in `playhub-live` and re-download; don't hand-edit it.
**OWED: add `ai.playhub://login-callback` to the Supabase Auth redirect allow-list** — password reset uses it
(hardcoded client-side); **invites do NOT** (mobile never passes `redirect_to`, so they use Site URL). A miss
silently falls back to Site URL, which looks like "link works but doesn't open the app". Play Console: new
package = new listing, existing installs can't upgrade across it. `flutter analyze` not run (standing
preference); needs a clean rebuild (`flutter clean`) since the Gradle namespace changed.

### 2026-07-29 — AAB build on main via ui-revamp-aab.yml (merged `ui-revamo`; my release-aab.yml deleted)
**GOTCHA for future agents: check the other branches before doing platform/CI work.** `ui-revamo` carried an
unmerged [ui-revamp-aab.yml](.github/workflows/ui-revamp-aab.yml) (signed AAB, `ANDROID_KEYSTORE_*` secrets →
`android/key.properties`) **and had already done the `ai.playhub` rename**; a duplicate `release-aab.yml` was
written on main in ignorance of it and is now **deleted**. `ui-revamo` is merged into main; the surviving AAB
workflow triggers on **`ui-revamo` AND `main`** and pins **versionName 1.1 / versionCode 2** via
`--build-name`/`--build-number` (pubspec stays `0.1.0+1`). Conflict resolutions kept: **main's
`google-services.json`** (the real `playhub-live` download — `ui-revamo`'s was hand-edited to `ai.playhub` while
still pointing at old project `playhub-348c7`) and **`ui-revamo`'s `build.gradle.kts`** (a superset — same
`ai.playhub` plus the `key.properties`-driven release signingConfig, falling back to debug when the file is
absent). **versionCode 2 is hardcoded** → Play rejects a repeat, so bump per release or use `github.run_number`.
**Signing depends entirely on the `ANDROID_KEYSTORE_*` repo secrets being set** — absent them the build silently
debug-signs and Play will reject the artifact. The local upload keystore was reported LOST; the base64 secret in
GitHub is the only known copy (recoverable via an artifact, since log masking doesn't cover artifacts).

### 2026-07-20 — parent/student dashboard FEE-LOCK (pay-to-unlock when fee pending 3+ days)
Owner decision: a parent/student now gets their whole dashboard replaced by a pay-to-unlock screen when a
linked student has an unpaid invoice (`issued`/`partial`/`overdue`, balance>0) whose `due_date` is
≥ `kFeeLockGraceDays` (**3**) days in the past. New `feeLockProvider` + `FeeLockState` +
`kFeeLockGraceDays` in [parent_providers.dart](apps/mobile/lib/features/parent/data/parent_providers.dart)
(queries invoices across `myLinkedStudentIdsProvider` — works for student role too, RPC returns own id);
new [fee_overdue_lock_page.dart](apps/mobile/lib/features/parent/presentation/fee_overdue_lock_page.dart)
(mirrors owner `PaywallPage`, reuses `PaymentCheckout.payInvoice`); wired into the parent+student branches of
[role_dashboard.dart](apps/mobile/lib/features/dashboards/role_dashboard.dart) (optimistic — shows shell
while lock loads). **Keyed off `due_date`, NOT invoice `status='overdue'`** — so the 3-day lock fires
independently of the `mark-overdue` cron (which flips status only after `due_date + late_fee_grace_days`,
default 5). **This is a UX GATE, not RLS** — an old build/raw API still reads the data; it only forces
payment before the shell renders. To change the threshold, edit `kFeeLockGraceDays`. Not yet
academy-configurable (hardcoded 3). `flutter analyze` not run (standing preference).

### 2026-07-15 — FIX: head_coach attendance list was center-only (42501 on cross-sport save) + review log
`todaysBatchesProvider` ([attendance_providers.dart](apps/mobile/lib/features/attendance/data/attendance_providers.dart))
scoped a head_coach by CENTER only, but `can_mark_attendance` for head_coach = `batch_in_my_center` AND
`batch_in_my_sport`, so today's cross-sport in-center sessions were listed and 42501'd on save. Split the
merged `center_admin || head_coach` branch: **center_admin stays center-only; head_coach now also sport-filters**
via `mySportIdsProvider` (mirrors `myBatchesProvider`). **Don't re-merge those two branches.** A max-effort
`/code-review` of this session's diff (15 findings — a `create-saas-order` stale-invoice money bug, `event_form`
center still unrestricted, trial cap counts trainers, + more) is logged in [HANDOFF.md](HANDOFF.md) →
"Code review — 2026-07-15". `flutter analyze` not run (standing preference).

### 2026-07-14 — Trainers section (trainers = coaches rows, kind='trainer') + removed from Team invite
Owner decision: trainers get the SAME functionality/access as coaches (for center_admin + head_coach), as a
separate section. Modeled as coaches rows tagged `kind`
([20260714000400](supabase/migrations/20260714000400_coaches_kind.sql) — **applied live**; default 'coach'),
reusing the ENTIRE coaches stack (form, center/sport scoping, RLS `can_manage_coach_record`, documents,
invite). Mobile: `Coach.kind`; [coach_form_page](apps/mobile/lib/features/coaches/presentation/coach_form_page.dart)
parameterized by `kind` (labels, saved kind, invite role — a trainer record mints a **role=trainer** login);
[coaches_tab](apps/mobile/lib/features/coaches/presentation/coaches_tab.dart) gains a **[Coaches | Trainers]**
`AppPillTabs` toggle (filters by kind, FAB creates that kind) so Trainers is reachable **everywhere Coaches
is** (owner bottom-tab + head_coach Manage row) with NO shell/nav change. The batch **primary-coach** picker
filters `kind='coach'` (trainers assist via `batch_staff`, not `batches.coach_id`). Trainer is removed from
the generic **Team-invite** dropdown (added to `_recordBackedTargets`) — invited from the trainer record's
"Login & access" instead, like coach. **RLS unchanged** (`can_manage_coach_record` scopes both;
`can_provision_role(trainer)` allows center_admin/head_coach — both outrank trainer). **OWED: web-admin
`gen:types`** (coaches.kind). **RIPPLES (not fixed):** `coachesProvider` returns BOTH kinds, so "Coaches"
counts/stats (home, KPI, growth) now include trainers — scope to `kind='coach'` if it matters; and the trial
2-coach-record cap now counts coaches+trainers combined. `flutter analyze` not run (standing preference).

### 2026-07-14 — batch form: coach picker scoped to center (+ sport)
The batch "Coach *" dropdown listed ALL academy coaches (`optionsOf: (coaches) => coaches`). Now scoped: pick
a center → coaches IN that center; also pick a sport → coaches in that center who TEACH that sport. New
`coachIdsForSportProvider(sportId)` (reverse of `coachSportsProvider`) drives the sport filter;
[batch_form_page](apps/mobile/lib/features/batches/presentation/batch_form_page.dart) filters `optionsOf` by
`c.centerId == _centerId` + membership in that set, and clears `_coachId` on center/sport change. Applies to
create AND edit — in edit, a saved coach not in the narrowed center+sport set falls back to "— select —" (the
`_AsyncDropdownField` value-guard) so the user re-picks. Client UX only; RLS is unchanged (batches don't
RLS-check coach↔sport, so this is a UI convenience, not a hard gate). `flutter analyze` not run (standing pref).

### 2026-07-14 — REVERT hide-own-head_coach RLS (it broke head_coach sports); hide own in the LIST instead
`20260714000100` (hide a head_coach's OWN coach record via RLS) was a REGRESSION. `myCoachRecordProvider`
reads `coaches where user_id = auth.uid()` to derive a head_coach's sports (`mySportIdsProvider`) + their
manageable batches — so with their own row RLS-hidden they got ZERO sports in the batch/student/coach sport
pickers (reported: "selected north but no sports show") and an empty coach-shell batch list.
[20260714000300](supabase/migrations/20260714000300_head_coach_own_coach_readable.sql) — **applied live +
verified** (own row readable=1, sees_own=t) — reverts `coach_is_foreign_head_coach` to **PEER-ONLY** (own is
readable/manageable again; OTHER head coaches still hidden). Hiding the own record from the Coaches LIST is
now **client-side** ([coaches_tab](apps/mobile/lib/features/coaches/presentation/coaches_tab.dart) `_filter`
drops `c.userId == currentUserId` for a head_coach viewer). **LESSON: RLS gates data ACCESS, not list
PRESENTATION — never hide a row via RLS that the app must read for its own scoping.** RLS fix is live (any
APK); the list filter needs a rebuild. **Supersedes the `20260714000100` entry below.**

### 2026-07-14 — batch/student/event forms: same center scoping as the coach form
Swept the sibling create forms for the coach-form problem. **batch_form + student_form** now restrict the
Center dropdown to a center-scoped role's own center(s) (`myCenterIdsProvider`) + auto-select their primary
center in initState — the center IS RLS-gated for both (batch via `can_manage_batch_fields`, student via
`can_manage_student`), so a head_coach/center_admin picking a foreign center previously 42501'd on save
(the change log had flagged this for students). Their sport pickers were already center-scoped +
head_coach-restricted. **event_form**: moved the (optional) Center picker ABOVE the Sport picker so sports
scope to the chosen center instead of flashing the academy-wide union first (event center is optional +
sport isn't RLS-gated → cosmetic). All three clear the selected sport on center change. Client UX only, RLS
unchanged. Supersedes the "batch/student NOT changed" note in the coach entry below. **NOT changed:** the
secondary center pickers (coach/student bulk import, inventory forms, lead-convert). `flutter analyze` not
run (standing preference; CI compiles).

### 2026-07-14 — coach form: center-first + sports scoped to the chosen center (role-aware)
The New/Edit-coach form showed "Sports coached" ABOVE the center and sourced it from
`academyCenterSportsProvider` (EVERY academy sport), so an owner saw all sports before/without picking a
center. Reworked [coach_form_page](apps/mobile/lib/features/coaches/presentation/coach_form_page.dart):
**Center (Assignment) now renders BEFORE Expertise**; the sports block is scoped to the SELECTED center
(`centerSportsProvider`) and shows a "pick a center first" hint until one is chosen (selection cleared on
center change). **Role scoping:** center_admin/head_coach get their primary center auto-selected (initState)
+ the center dropdown restricted to their own center(s) (`myCenterIdsProvider`); a **head_coach**'s sports
are further narrowed to the sports THEY own (`mySportIdsProvider`) — they may only qualify a coach for their
own sports. `SportMultiSelect` gained `centerId` + `restrictToSportIds` (mirrors `SportPicker`, now uses
`_resolveSports`); it's coach-form-only, no other caller. **Client UX only — RLS unchanged.** `flutter
analyze` not run (standing preference; CI compiles it). **Known same-gap, NOT changed:** batch/student forms
scope sports by center but don't auto-select/restrict the center for center-scoped roles.

### 2026-07-14 — SaaS upgrade now has verify-on-return (was webhook-only → silent drop)
Root-caused "upgraded but still capped": the self-serve SaaS upgrade recorded a payment ONLY via the
PLATFORM Razorpay webhook, so a captured charge silently dropped when the webhook didn't fire — academy
stuck on `trial`, caps never lifted (hit live on "Paradox": invoice `issued`, 0 saas_payments). Added
verify-on-return, mirroring the fee flow: new edge fn [verify-saas-payment](supabase/functions/verify-saas-payment/index.ts)
+ [_shared/saas_razorpay_record.ts](supabase/functions/_shared/saas_razorpay_record.ts) `confirmAndRecordSaasRazorpay`
re-confirm via the Razorpay Payments API (PLATFORM creds) and record into `saas_payments`;
[create-saas-order](supabase/functions/create-saas-order/index.ts) now returns `invoice_id`; mobile
`PaymentCheckout.paySaasSubscription` calls verify after the sheet closes and only reports success on
`captured`. **Idempotency:** new partial unique index on `saas_payments.razorpay_payment_id`
([20260714000200](supabase/migrations/20260714000200_saas_payments_unique_razorpay.sql) — applied live) so
verify + webhook converge (webhook keys on unique_event_id=eventId, verify on `razorpay:<paymentId>`; they'd
otherwise double-record). **Deployed this session:** verify-saas-payment (JWT on) + create-saas-order. Webhook
stays the async backstop. Mobile needs a rebuild. `flutter analyze` not run (standing preference).

### 2026-07-14 — self-serve SaaS upgrade wired into SubscriptionPage (was a request stub)
Pulled the deferred v1.x self-serve plan-change forward (owner decision). The pricing page's
"Request change" snackbar (`We've noted your interest…`) is replaced with a real Razorpay checkout:
[subscription_page](apps/mobile/lib/features/subscription/presentation/subscription_page.dart) `_PlanCard`
is now a `ConsumerStatefulWidget` whose button calls `PaymentCheckout.paySaasSubscription(planCode: plan.code)`
→ `create-saas-order` (PLATFORM Razorpay, NOT the academy's own gateway) → webhook + `reactivate_paid_subscription`
activate the academy server-side; on success it invalidates `mySubscription`/`trialLimits`/etc. **Backend
already supported this** (`create-saas-order` already takes any `plan_code`; deployed 2026-06-30) — pure mobile
change, needs a rebuild. **Removes super_admin oversight of plan changes** (any owner can now self-upgrade). To
work in prod the PLATFORM Razorpay keys + `payment.captured` webhook must be live. `flutter analyze` not run
(standing preference; recommend running before relying on the APK).

### 2026-07-14 — head_coach hides ALL head_coaches incl. OWN (widens 20260714000000)
Owner follow-up: a head_coach should see/manage NO head_coach records in Coaches, not just peers — supersedes
the "own record unaffected" note in the entry below. [20260714000100](supabase/migrations/20260714000100_head_coach_hide_own_coach_record.sql)
— **applied live + verified** (sees_OWN=f, sees_PLAIN=t) — drops the `u.id <> auth.uid()` self-carve from
`coach_is_foreign_head_coach` so it now matches ANY head_coach when the actor is a head_coach. The read helper +
coaches_update + can_manage_coach call it by name → auto pick up the change. Sport authority unaffected
(`head_coach_owns_sport` is SECURITY DEFINER). Fn name keeps "foreign" for continuity (see its comment). RLS-only.

### 2026-07-14 — head_coach can no longer see/edit a PEER head_coach (RLS)
Org-hierarchy: a head_coach manages coaches/trainers under them, not other head coaches.
Was NOT enforced — `can_manage_coach_record` is center-scoped, so a head_coach could edit
any coach in their center incl. another head_coach. New `coach_is_foreign_head_coach(coach_id)`
(true only when the ACTOR is a head_coach and the target is a DIFFERENT head_coach) is AND-ed
(negated) into `head_coach_sees_coach` (read → peer drops out of the coaches list automatically,
no Dart change), `coaches_update` (can't edit a peer), and `can_manage_coach` (can't retag a
peer's sports). Own record + plain coaches unaffected; owner/admin/center_admin never restricted.
[20260714000000](supabase/migrations/20260714000000_head_coach_no_peer_coach_mgmt.sql) — **applied
live via the Management API this session** + verified by reproduction (sees_peer=f, peer_update_rows=0;
sees_own/plain=t). RLS-only, no APK rebuild. **OWED: commit the migration file** (pgTAP not added).

### 2026-07-14 — coach form pre-checks the trial coach cap (was a raw 403) + GOTCHA
Diagnosed a head_coach "database error on coach create": it was the free-trial coach cap
(RESTRICTIVE policy `trial_quota_coaches_insert`, `TrialLimits.maxCoachRecords = 2`) returning
`42501` — surfaced raw because the June-30 APK predates the upgrade-prompt gating AND the coach
FORM didn't pre-check. **GOTCHA (for any future "can't create coach" report): a head_coach's OWN
auto-minted `coaches` record counts toward the 2-cap**, so a trial head_coach can create only ONE
more coach; the next insert 403s. Fix: [coach_form_page](apps/mobile/lib/features/coaches/presentation/coach_form_page.dart)
`_save` now pre-checks `trialLimitsProvider.coachesReached` on CREATE → `showUpgradePrompt`
(role-aware); the list FAB already did. RLS stays the hard gate; edit is unaffected (quota is
INSERT-only). Does NOT raise the cap — to add more coaches, flip the academy to `active` or upgrade.
`flutter analyze` not run (standing preference); needs a rebuild to ship.

### 2026-07-11 — head_coach can now invite parent/student logins (was owner/admin/center_admin only)
Owner decision — supersedes the 2026-07-07/07-09 "a head_coach can't mint student/parent logins" notes. A
head_coach already creates + manages students in their center, so they may now mint those students' parent +
student LOGINS. Widened ONLY the parent/student branch of `can_provision_role`
([20260711000000](supabase/migrations/20260711000000_head_coach_invite_parent_student.sql) — **applied
live**) to accept a head_coach scoped to their own center(s); **`can_admin_center_scope` left untouched** (the
finance-read gate reuses it). Client mirror: `head_coach.invitableRoles` in
[capabilities.dart](apps/mobile/lib/features/auth/data/capabilities.dart) += `parent`/`student` (invariant
#3). Also **gated the student-edit "Logins & access" cards on `canInvite`** — they rendered unconditionally,
so a plain coach saw invite cards that 403'd; now shown to owner/admin/center_admin/head_coach, hidden from
coach. **No `invite-user` redeploy needed** (it calls `can_provision_role` at runtime). `flutter analyze` not
run (standing preference).

### 2026-07-11 — generic invite dropdown is staff-only; coach/parent/student are record-backed invites
The generic "Invite team member" sheet used to offer `coach`/`parent`/`student` as target roles, which
minted a **dangling login** (a coach with no `coaches` row → invisible in the coach list + can't own a
batch; a student with no `students` row; a parent linked to no student). Now
[invite_user_sheet.dart](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart) filters
`_recordBackedTargets = {coach, parent, student}` OUT of the role dropdown — they're invited only from
their record's own profile (Coaches → "invite login" with `linkCoachId`; a student's "Logins & access" with
`linkToStudentId`/`linkStudentLoginId`), which links the login to a real row. **head_coach stays in the
dropdown — its invite mints the coach record.** `capabilities.invitableRoles` is UNCHANGED (still lists all
of them) so `canInvite()` keeps gating those record-backed invite tiles; the filter is dropdown-only. Don't
re-add coach/parent/student to the generic dropdown. `flutter analyze` not run (standing preference).

### 2026-07-11 — GOTCHA: a SCOPED `delete` under `session_replication_role=replica` skips FK cascades
Surfaced by /code-review (#11) on the `20260710000000` junk-row cleanup. `replica` disables FK triggers, so
`delete from batches where …` does NOT cascade to `batch_enrollments`/`attendance`/etc. — a *scoped* delete
orphans children (dangling FK, no error, since RI is off too). It's fine in `wipe.sql` (deletes the WHOLE
tenant set) but NOT for a partial delete. **Moot on our DB** (fully wiped after that migration; a fresh
`seed.sql` has none of those junk rows). Not fixed in-place — the migration is applied + immutable
(invariant #5). **Lesson: for a scoped delete of parents that have children, delete children first, or don't
run it under `replica`.**

### 2026-07-11 — invite-user rejects a center-less center_admin/head_coach (server-side; deployed)
Found by /code-review (#4). [invite-user](supabase/functions/invite-user/index.ts) now returns a clear 400
("a center admin/head coach must be assigned a center") when `effectiveCenterId` is null for those roles,
instead of letting `handle_new_auth_user` insert a center-less row that violates the new
`users_center_scoped_role_needs_center` CHECK and aborts the signup with an opaque DB error. Defense-in-depth:
the mobile invite form already requires it, so this only guards raw-API / web-admin / non-form callers.
**Deployed this session** via `npx supabase functions deploy invite-user --project-ref <ref>` (JWT on).

### 2026-07-11 — /code-review hardening: dropdown value-guards, freeze-aware create errors, scoped HC sports
Follow-ups from the review (all mobile, no deploy). **(#8)** Every center dropdown (batch/coach/student
forms — `_AsyncDropdownField` / `AppDropdownField`) AND the shared
[SportPicker](apps/mobile/lib/features/sports/presentation/sport_picker.dart) now fall back to
"— select —" when their stored value isn't in the current options (edit-mode deactivated center / disabled
sport / head_coach restrict) instead of tripping `DropdownButtonFormField`'s value-in-items assert — the
validator then flags it. **(#9)** `createStudent`/`createCoach`/`createBatch` surface "your academy's plan
is paused" (vs the misleading "own center") when a frozen subscription is the real RLS block —
`AcademySubscription.isBlocked` recomputes vs `now()`, so it catches a mid-session trial lapse; the
update/edit blocks keep the "own center" wording (same-class residual). **(#6)** the head_coach invite's
sport chips are scoped to the chosen center (`centerSportsProvider`) + cleared on center change. **(#5)**
`createBatch` uses `.maybeSingle()` + a clean 42501 like its peers. `flutter analyze` not run (standing pref).

### 2026-07-11 — batch form: Center before Sport + SportPicker value-guard (fixes a dropdown assert)
Found by /code-review. The batch form rendered Sport ABOVE the (now-required) Center and never reset the
sport when the center changed, so picking a sport then a center left `_sportId` out of the re-scoped list →
`DropdownButtonFormField` "one item with value" assert (debug) / a batch tagged with a sport its center
doesn't offer (RLS doesn't check sport-at-center). Fix: [batch_form_page.dart](apps/mobile/lib/features/batches/presentation/batch_form_page.dart)
puts Center first and clears `_sportId` in the center `onChanged`. Also hardened the shared
[SportPicker](apps/mobile/lib/features/sports/presentation/sport_picker.dart) to fall back to "— select —"
when its `value` isn't in the current scope (center change / sport disabled at the center / head_coach
restrict) instead of asserting — benefits every caller (batch/coach/lead/event). `flutter analyze` not run.

### 2026-07-10 — FIX: lead→student conversion (regression from students.center_id NOT NULL)
Found by /code-review: the 20260710000000 `students.center_id` NOT NULL constraint broke `convert_lead()`
— it inserted the student with `v_lead.preferred_center_id`, which the in-app lead form never captures, so
EVERY lead→student conversion hit an opaque NOT NULL violation with no recovery.
[20260710000200](supabase/migrations/20260710000200_convert_lead_center.sql) — **applied live** — makes
`convert_lead` resolve center = `coalesce(lead.preferred_center_id, chosen batch's center)` and raise a
CLEAR error if neither (signature unchanged ⇒ **no edge-fn redeploy needed**). The convert sheet
([lead_convert_sheet.dart](apps/mobile/lib/features/leads/presentation/lead_convert_sheet.dart)) now has a
**required Center picker** (defaults to the lead's preferred), and `LeadsRepo.convert(centerId:)` stamps it
onto `leads.preferred_center_id` before invoking the edge fn (RLS `leads_write_update` lets an admin set
it), so the RPC always resolves a center. `flutter analyze` not run (standing preference).

### 2026-07-10 — batch requires a center; head_coach invite requires ≥1 sport (mints a coach record)
Two more creation-chain guards. **(1) Batch → center:** `batches.center_id` is now **NOT NULL**
([20260710000100](supabase/migrations/20260710000100_batch_center_required.sql) — applied live; FK →
RESTRICT), and [batch_form_page](apps/mobile/lib/features/batches/presentation/batch_form_page.dart)
requires **Center \*** (validator + save-guard). With sport_id + coach_id already NOT NULL, every batch is
fully scoped (center + sport + coach). **(2) head_coach → ≥1 sport:** inviting a head_coach now requires a
name + **≥1 sport** (sports multi-select in
[invite_user_sheet](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart)); on submit it
**mints a `coaches` record** (name + center + those sports) and passes it as `link_coach_id`, so the auth
trigger stamps `coaches.user_id` on accept and the head_coach actually **owns** sports
(`head_coach_owns_sport`). **CLOSES the "invited head_coach owns zero sports" gap** from the 2026-07-09
entry. Owner-chosen flow (vs "invite from an existing coach record"). A failed invite now ROLLS BACK the minted
coach record (no orphan, no consumed trial slot, no double-mint on retry; found by /code-review), and the
trial coach-record cap is pre-checked before minting. Still UI-only (the
head_coach↔sport link can't be a DB constraint — join-table cardinality), so a raw-API head_coach invite
without a coach record still yields a sportless head_coach. **OWED:** web-admin `gen:types`
(`batches.center_id` now non-null); `flutter analyze` not run (standing preference).

### 2026-07-10 — trial-cap surfaces now open an upgrade PROMPT (was dead-end snackbars)
Reaching ANY free-trial quota (sports / coaches / students / batches / staff logins) now opens a shared
upgrade dialog — [showUpgradePrompt](apps/mobile/lib/features/subscription/presentation/upgrade_prompt.dart),
whose "View plans" routes to `SubscriptionPage` (same destination as `PaywallPage`) — instead of the old
inconsistent snackbars (`_showTrialLimit`, a raw `SnackBar` for sports, `AppSnackbar.error` for invite).
**Role-aware (added 2026-07-11, /code-review):** only the owner (`manageSubscription`) sees "View plans";
admins/center_admins get "Ask your academy owner to upgrade" + OK (no dead-end to a page they can't act on).
**Reuse `showUpgradePrompt(context, message: <TrialLimits.*Message>)` for any NEW quota gate — don't add a
fresh snackbar.** RLS is still the hard gate. **Decision (owner):** did NOT make archiving a coach/student/
batch free its trial slot (the counts still include archived rows) — hitting the cap routes to upgrade
instead. (Sports stay swap-by-delete since remove is a hard-delete.) `flutter analyze` not run (standing preference).

### 2026-07-10 — creation-chain dependencies now enforced at the DB (were UI-only)
"Coach needs a center", "batch needs a sport + coach", "student needs a center", and
"center_admin/head_coach login needs a center" were ONLY Flutter-form guards — the columns were
nullable, no CHECK asserted them, and the RLS insert policies **explicitly allow a null center**
(`p_center_id is null or …`), so any non-UI path (CSV import, raw API, an invite omitting center)
created powerless / isolation-leaking rows.
[20260710000000](supabase/migrations/20260710000000_enforce_creation_chain_constraints.sql) —
**applied live via the Management API this session** — makes `coaches.center_id`, `students.center_id`,
`batches.sport_id`, `batches.coach_id` **NOT NULL**, adds CHECK `users_center_scoped_role_needs_center`
(center_admin/head_coach ⇒ center), and flips those 4 FKs **ON DELETE SET NULL → RESTRICT** (deleting a
center/sport/coach still referenced is now **blocked — reassign first**, was silent-orphan). Pre-req
cleanup baked into the migration: null-center rows in single-center academies were backfilled (this also
fixed diya's null center), and un-backfillable junk in two abandoned test academies ("am" = 0 centers;
"Elite" = a coachless batch) was **deleted**. **NOT enforced (owner decision): "coach needs ≥1 sport"** —
sports live in the `coach_sports` join table inserted in a SEPARATE request, so no column/CHECK/deferred-
trigger can assert it without an atomic-RPC rewrite; stays UI-only. **Same pass:** the coach + student
**CSV importers** now require a target center (+ ≥1 sport for coaches, via `setCoachSports`) — they
inserted null-center rows and would hard-fail these constraints otherwise. **OWED:** web-admin
`npm run gen:types` (center_id/sport_id/coach_id are now non-null in the generated types — needs local
DB, not run here); if `seed.sql`/`create_demo_users.mjs` are re-run they must supply center/sport/coach;
`flutter analyze` not run (standing preference).

### 2026-07-09 — invite form: head_coach now REQUIRES a center (was optional)
An admin-tier inviter (owner/academy_admin) could invite a head_coach **without picking a center**,
minting `users.center_id = NULL` → a **powerless** head_coach: their authority is center+sport gated
via `current_user_in_center()`, so a center-less head_coach can create/manage nothing (batches,
students, coaches) — it is NOT "academy-wide". Fix in
[invite_user_sheet.dart](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart): new
`_centerRequiredTargets = {center_admin, head_coach}` now gates the submit guard, the "Center *"
label, and the empty-centers "create a center first" message (coach/trainer stay optional — they're
batch-assignment scoped, so center-less is fine and the "academy-wide until assigned" hint is accurate
for them). **Still-open gap (NOT fixed):** the invite sheet never links a `coaches` record for a
head_coach (no `link_coach_id` — that only flows from the coach-login preset, which forces role=coach),
so an invited head_coach still owns **zero sports** (`head_coach_owns_sport` finds no linked coaches row)
until a coach record is linked to their login out-of-band — there is no clean in-app "head_coach + coach
record + sport" provisioning flow yet. `flutter analyze` not run (standing preference).

### 2026-07-07 — head_coach STUDENT read widened to their CENTER (reverses 20260608000500)
20260608000500 narrowed a head_coach's student read to "students enrolled in a batch in their center
AND sport", which **dead-ended onboarding**: a head_coach can create a student (`can_manage_student`
is center-wide) but the new/unenrolled student was invisible to them AND absent from the batch
**Enrol** picker (both draw from the students read), so it could never be enrolled. The head_coach
branch of `head_coach_sees_student` is now `public.student_in_my_center(p_student_id)` — every student
in their center(s)/null-center, matching their center-wide write.
[20260707000000](supabase/migrations/20260707000000_head_coach_center_wide_students.sql), **applied
live to the hosted DB this session via the Management API** (+ committed to migrations/). **Owner-approved
tradeoff:** a head_coach now also sees OTHER sports' students in their center (student sport-narrowing
gone; **batches + coaches stay center+sport-scoped**). **Backend-only — no mobile change** (the mobile
`studentsProvider` already relies on RLS for head_coach). Rollback = restore the 20260608000500 body;
`gen:types` not needed (function body only).

### 2026-07-07 — student create: email toggle sends a parent OR student login invite
The New-student form now provisions a login at creation time. A **[Parent | Student] SegmentedButton +
single email field** ([student_form_page.dart](apps/mobile/lib/features/students/presentation/student_form_page.dart))
decides both where the email is stored (`parent_email` vs the student's own `email` column) and which
magic-link invite fires on save: `role=parent` (linkToStudentId + relationship=parent) or `role=student`
(linkStudentLoginId), mirroring the edit-screen "Logins & access" presets via `InviteRepo.invite`.
**Invite is best-effort** — the student row is created first, so an invite failure is surfaced but
non-fatal (student is kept; retry from their profile). **Shown only when the inviter can provision BOTH
parent + student** (`caps.canInvite`, i.e. owner/admin/center_admin); a **head_coach** can create students
but not those logins, so they keep the plain parent-email field with no invite (edit mode likewise). Email
is **optional** — blank = no invite, create as before. `flutter analyze` not run (standing preference).

### 2026-07-07 — owner signup: academy name carried into SetupAcademyPage (no re-typing)
Fixed a double academy-name entry. `signup_page` only calls `bootstrap_owner_academy` when
`auth.signUp` returns a session synchronously (email confirmation **OFF**); with confirmation **ON**
— the real path now that SMTP is configured — `signUp` returns no session, the academy name typed at
signup was silently dropped (it lives only in `user_metadata`, read by nothing), and after
verify→login `SetupAcademyPage` re-prompted for it. Fix ("carry over", user-chosen):
[setup_academy_page.dart](apps/mobile/lib/features/dashboards/setup_academy_page.dart) `initState` now
**prefills** `_name` from `currentUser.userMetadata['academy_name']` (still editable; the
trial-vs-subscribe choice is unchanged). **Contract:** signup's `signUp(data: {academy_name})` is now
read back by SetupAcademyPage — don't drop `academy_name` from the signup metadata. **Residual
(unchanged):** the confirmation-OFF path still auto-bootstraps a trial at signup and never shows the
setup/subscribe screen (owners there skip the plan choice). `flutter analyze` not run (standing preference).

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
