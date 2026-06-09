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
