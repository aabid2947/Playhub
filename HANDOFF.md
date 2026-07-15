# Handoff — `ui-revamo` branch (as of 2026-07-15)

Snapshot for whoever picks this up next. Durable per-change detail lives in the
[CLAUDE.md change log](CLAUDE.md#change-log--things-future-agents-must-know); this
is the "where things stand + what's next" summary.

## Snapshot

| | |
|---|---|
| Branch | `ui-revamo` (working tree clean, in sync with `origin/ui-revamo`) |
| HEAD | `4a62d4e` — *feat: Trainers section* |
| Latest APK | CI **`build-apk` run 29424259171** (✅) — GitHub → Actions → Artifacts |
| Backend | migrations `20260714000000`–`…000400` applied **live**; 2 edge fns deployed (below) |
| Supabase project | `hrawgduftgslwsdgzliy` (hosted; this session used it directly) |

**Workflow used this session:** each mobile change → commit → push to `ui-revamo`
→ CI `build-apk` produces the APK (the user tests on it — `flutter analyze` is
**not** run locally per standing preference, so **CI is the compile gate**).
Migrations/edge-fns are applied to the **hosted** DB directly (see
[Applying changes](#applying-changes)).

## What shipped this session (newest → oldest)

Coaching-staff, forms, and SaaS-upgrade work on top of the UI revamp.

| Commit | Summary |
|---|---|
| `4a62d4e` | **Trainers section** — trainers modeled as `coaches` rows tagged `kind='trainer'`; `[Coaches\|Trainers]` toggle in `CoachesTab`; removed from Team invite; batch primary-coach picker excludes trainers |
| `fd521d3` | Batch **coach picker** scoped to center (+ sport) via `coachIdsForSportProvider` |
| `d484be7` | **Revert** `…000100` (it broke head-coach sports) + hide own record in the coaches *list* client-side |
| `4091324` | Center scoping in **batch/student/event** forms (coach-form parity) |
| `802178c` | **Coach form**: center-first, sports scoped to the chosen center, role-aware |
| `c5af49e` | **SaaS verify-on-return** (was webhook-only → silent drops) |
| `4c589ae` | **Self-serve SaaS upgrade** checkout (SubscriptionPage → Razorpay) + head_coach hides all head coaches |
| `576175e` | head_coach can't see/edit a **peer** head_coach (RLS) |
| `9370250` | Coach form **pre-checks the trial coach cap** → upgrade prompt (was a raw 403) |

**Verified, no change needed** (audited live): a **center_admin** can create/edit
coaches, head coaches, and batches in their center(s); the **attendance** mechanism
+ per-role scoping (owner=any batch, center_admin=own center, head_coach=center+sport)
already matches spec — entry points are Home → "Today's Sessions" / "Attendance overview".

## Backend applied live this session

Migrations (added to `supabase/migrations/`, **applied to the hosted DB**):
- `20260714000000` — head_coach peer exclusion (`coach_is_foreign_head_coach`).
- `20260714000100` — hid head_coach's OWN record — **REVERTED** by `…000300` (broke their sports).
- `20260714000200` — partial unique on `saas_payments.razorpay_payment_id` (verify/webhook convergence).
- `20260714000300` — head_coach own record readable again (peer-only). **Current head_coach behavior.**
- `20260714000400` — `coaches.kind` (`'coach'|'trainer'`, default `'coach'`).

Edge functions **deployed** (`npx supabase functions deploy … --project-ref hrawgduftgslwsdgzliy`):
- `verify-saas-payment` (**new**, JWT on) + `_shared/saas_razorpay_record.ts`.
- `create-saas-order` (redeployed — now returns `invoice_id`).
- `razorpay-webhook` **not** changed this session (still the async backstop).

## Owed / follow-ups (not done)

1. **web-admin `gen:types`** — new `coaches.kind` column (and earlier owed columns from prior sessions). Needs a local Supabase/Docker; not runnable in this session.
2. **✅ DONE (= code-review #12) — "Coaches" count stats include trainers** — home / growth / super-admin "Coaches" consumers now scope to `kind='coach'` (via `Coach.isCoach`). `coachesProvider` itself still returns both kinds by design (the Coaches/Trainers tab filters it).
3. **Trainer → batch assignment UI** — `batch_staff` (assign trainers/assistants to a batch) has backend + RLS but **no Flutter UI**. This is the one unbuilt piece of trainer management.
4. **`role_dashboard` "No profile row found." dead-end** — orphaned-login state; make it a clear message + Sign out button (client-only).
5. **Secondary center pickers** unrestricted for center-scoped roles: `coach_bulk_import`, `student_bulk_import`, `inventory_item_form`, `movement_sheet`, `lead_convert_sheet` (lower stakes).
6. **Trial cap nuance** — the 2-coach-record trial cap now counts coaches **+** trainers combined (shared cap). Split if undesired.

## Code review — 2026-07-15 (`git diff af47af2..HEAD`, max effort)

A `/code-review` at max effort ("any other similar problem we discussed")
surfaced **15 findings** on this session's work (SaaS-upgrade + forms +
Trainers), ranked most-severe first. **#2, #3, #6, #7, #9, #10, #11, and #12 are
FIXED**; the rest are open. Items 2/4/5/12 above overlap and are detailed here.

### Correctness / money

1. **`create-saas-order/index.ts` (~L98)** — a self-serve plan **upgrade reuses a stale open invoice**, charging the OLD plan's amount for the NEW plan. *Trigger:* academy has an unpaid issued/past_due SaaS invoice, taps a different (pricier) plan → `plan_id` is repointed but `invoiceAmount` = the old invoice's `total_amount` → Razorpay charges the old amount → capture activates the pricier plan for less. **Money bug**, exposed by the new SubscriptionPage upgrade path. Backend fix + redeploy.
2. **✅ FIXED — `attendance_providers.dart:66`** — `todaysBatchesProvider` scoped a head_coach by CENTER ONLY; `can_mark_attendance` requires center AND sport → it listed cross-sport sessions → 42501 on save. Now split from `center_admin` and sport-filtered via `mySportIdsProvider` (mirrors `myBatchesProvider`); doc comment corrected.
3. **✅ FIXED — `event_form_page.dart` (~L246)** — the Center dropdown listed ALL centers (incl. inactive), unrestricted for center-scoped roles → a center_admin/head_coach picking an unmanaged center → `events_write_insert` (`can_manage_batches`) → 42501. Now drops inactive centers and restricts to `myCenterIds` for center-scoped roles (owner/admin keep the full list), with a value-guard; "— None —" (academy-wide) stays for everyone. Same pattern as coach/batch/student forms.
4. **`trial_limits.dart` (~L45)** — the free-trial 2-coach-record cap now counts `kind='trainer'` rows, so on a trial academy at the cap you can't add ANY trainer, and the block message says "2 coaches". (= Owed #6.)
5. **`payment_checkout.dart` (~L195)** — after a genuine SaaS capture, a verify timeout / non-map returns `CheckoutFailure` → shown as a RED error with NO provider refresh → a paying owner sees "failure" + stale trial state (the webhook reconciles server-side, contradicting the UI).
6. **✅ FIXED — `coaches_tab.dart` / `coach_bulk_import_page.dart`** — Import CSV on the Trainers tab inserted without `kind` (DB default `'coach'`) → silently created coaches. `CoachBulkImportPage` now takes a `kind` param (the tab passes `_kind`), writes `'kind'` on every insert, and shows kind-aware labels (title, center/sport pickers, trial note, errors) throughout.
7. **✅ FIXED — `coach_home_providers.dart:10`** — a trainer login resolves a non-null coaches row (trainers ARE coaches rows), so the coach shell treated them as a linked coach whose "my batches" (`coach_id == own`) was always empty (trainers are never a batch's primary coach; they assist via `batch_staff`). `myBatchesProvider` now has a trainer branch that resolves batches via `batch_staff` (keyed on the coaches row's `user_id`), mirroring the RLS `staff_on_batch` gate — empty only when they truly have no assignments (until the batch_staff assign UI lands, Owed #3). The "not linked" notice correctly no longer shows (they ARE linked).
8. **`_shared/saas_razorpay_record.ts` (~L38)** — SaaS verify records against the **client-supplied `saas_invoice_id`** without binding the Razorpay order→invoice (the fee path binds via a server-created `payment_attempts` row). A crafted call with a mismatched invoice id could mark the wrong own-academy invoice paid. Hardening gap, not a normal-flow break.
9. **✅ FIXED — `batch_detail_page.dart:52`** — `scopeOk` checked CENTER only for head_coach, so Edit/Enrol/Mark rendered for cross-sport in-center batches → 42501. Now AND-s a sport check for head_coach (`mySportIdsProvider`, null-sport falls back to center) mirroring `myBatchesProvider` / `can_manage_batch_fields`; center_admin stays center-only.
10. **✅ FIXED — `batch_form_page.dart` (~L305)** — editing a batch whose saved primary coach doesn't teach the selected sport blanked the coach dropdown and blocked re-save of an unrelated edit. `optionsOf` now always keeps the current `_coachId`'s coach in the options (changing center/sport still clears `_coachId`, so it only preserves an intentional selection; coach↔sport isn't RLS-gated so no 42501 risk).
11. **✅ FIXED — `coach_form_page.dart` (~L105)** — the center auto-select seeded `_centerId` from `profile.centerId` (primary only) while build restricts options to `myCenterIds` (home + grants) → no preselection if the primary center is inactive/not in the granted set. initState now computes the assignable set (their centers ∩ active — the SAME set build() offers), prefers the primary, and falls back to the sole assignable center (also covers a null primary with a single grant).
12. **✅ FIXED — `home_tab.dart:245`** (+ `growth_metrics.dart`, super-admin `academyCoachesProvider`) — "Coaches" counts/lists included trainers (cosmetic inflation). All three now scope to `kind == 'coach'` via a new `Coach.isCoach` getter (home/growth filter the shared `coachesProvider` list; the super-admin query adds `.eq('kind','coach')`). (= Owed #2.) NOTE: super-admin no longer lists trainers at all — a Trainers view there is a separate follow-up.

### Cleanup / conventions

13. **Center-picker scoping is copy-pasted** across coach/batch/student forms with no shared abstraction, and the role source diverges (`currentProfileProvider` vs `caps.role`) — a fix in one silently misses the third. Extract an `assignableCentersProvider`/mixin.
14. **Coach/trainer labels** are scattered inline ternaries + hand-rolled capitalization (`_LoginAccessCard`); the repo pattern is a single `inventoryKindLabel()`-style helper (per CLAUDE.md). Add `coachKindLabel(kind)`.
15. **The head_coach RLS migrations (`20260714000000` / `…000300`) ship no pgTAP**, though the working rule is "schema change → RLS + pgTAP" and the prior narrowing of this same function shipped `rls_coaches_read.sql`.

## Live DB / demo state

- **Demo logins were deleted** except `superadmin@playhubdemo.in` (promoted to `super_admin`). The `create_demo_users.mjs` reset leaves all 9 demo logins as `academy_owner`/no-academy because GoTrue sets `app_metadata` **after** insert, so the auth trigger sees empty metadata — a **known gotcha** if you re-seed (see below).
- **Test academy "Paradox"** (`84e85bdc-…`): owner `aadilhussainpas@gmail.com`, head_coach `test2@gmail.com` (owns sport *baseball*, center *north*), parent `test@gmail.com`. Centers: north (baseball, Tennis) + south (baseball). 1 batch, 1 student.
- Full demo set + creds convention: [DEMO_CREDENTIALS.md](DEMO_CREDENTIALS.md). Surgical reset: `wipe.sql` → `seed.sql` → `create_demo_users.mjs --wipe-all-users` (see below).

## Key decisions & gotchas (read before changing related code)

- **RLS gates data ACCESS, not list presentation.** Hiding a head_coach's own `coaches` row via RLS broke `myCoachRecordProvider` (→ their sports/batches). Rule: never RLS-hide a row the app must read for its own scoping; filter it in the UI instead.
- **Trainers ARE `coaches` rows** (`kind='trainer'`) + a `role=trainer` login. Reuses the whole coaches stack. `batches.coach_id` = primary coach picks `kind='coach'` only; trainers assist via `batch_staff`.
- **head_coach asymmetry:** students are **center-wide**; batches/coaches/trainers are **center + sport**.
- **Stale APK is the recurring red herring** — several "bugs" this session were the user testing a June-30 APK. Always confirm the build before deep-diving.
- **`create_demo_users.mjs` role bug:** `admin.createUser` applies `app_metadata` after the row insert, so `handle_new_auth_user` defaults every demo login to `academy_owner`. Re-seeding needs a fix (set roles post-hoc, or a different creation path) or the demo logins come out wrong.

## Applying changes

- **SQL against the hosted DB** (no Docker/DB password): read the Supabase CLI token from **Windows Credential Manager** (`Supabase CLI:supabase`, UTF-8) → `POST https://api.supabase.com/v1/projects/hrawgduftgslwsdgzliy/database/query`. (Helper scripts were used from the session scratchpad.)
- **Edge functions:** `npx supabase functions deploy <name> --project-ref hrawgduftgslwsdgzliy` (needs `SUPABASE_ACCESS_TOKEN` from the same credential; no Docker needed for deploy).
- **APK:** push to `ui-revamo` → CI `build-apk` → download the artifact. `flutter analyze`/`test` are skipped locally (standing preference) — CI compilation is the gate.
- **Migrations are append-only + immutable once merged** (invariant #5). The hosted DB is applied manually — verify objects exist before assuming a repo migration is live.
