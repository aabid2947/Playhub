# PlayHub — Repository Structure

PlayHub is a **multi-tenant sports-academy management SaaS** (India-first: INR,
Asia/Kolkata, +91). It is a monorepo with three deployable surfaces over one
Supabase backend:

| Surface | Path | Stack | Audience |
|---|---|---|---|
| Mobile app (primary product) | [`apps/mobile/`](apps/mobile/) | Flutter 3.41 · Riverpod · go_router | All 9 roles (academy staff, parents, students) |
| Super-admin web console | [`apps/web-admin/`](apps/web-admin/) | Next.js 15 (App Router/RSC) · Tailwind v4 | Platform super-admins only |
| Backend | [`supabase/`](supabase/) | Postgres 16 (RLS) · Deno edge functions | — |

**The 9 roles** (DB enum `user_role`): `super_admin`, `academy_owner`,
`academy_admin`, `center_admin`, `head_coach`, `coach`, `trainer`, `parent`,
`student`.

```
playhub/
├── apps/
│   ├── mobile/        # Flutter app — the product
│   └── web-admin/     # Next.js super-admin console
├── supabase/          # migrations · edge functions · pgTAP tests · seed
├── scripts/           # repo-level helper scripts
├── .github/workflows/ # CI (one workflow per surface)
├── PLAN.md            # the full product/sprint plan (source of truth for scope)
├── DEMO_CREDENTIALS.md# seeded demo logins + per-role walkthrough
└── .env.example       # backend/secret env template
```

---

## Root files

| File | Description |
|---|---|
| [PLAN.md](PLAN.md) | Complete development plan: locked stack, sprint-by-sprint scope, version roadmap (v0.1→v3.0), risk register. Authoritative for *what's in scope*. |
| [DEMO_CREDENTIALS.md](DEMO_CREDENTIALS.md) | Seeded "PlayHub Demo Academy" logins (one per role, password `Demo@1234`) + what to demo as each role. |
| [.env.example](.env.example) | Template for backend secrets: Supabase URL/keys, Twilio, Gmail SMTP, Razorpay, Sentry. |
| [.gitignore](.gitignore) | Repo-wide ignores. |

---

## `apps/mobile/` — Flutter app

Feature-first architecture. Each feature is a folder under `lib/features/<name>/`
split into `data/` (models + Riverpod providers + repository functions) and
`presentation/` (pages + widgets). Cross-cutting code lives in `lib/core/`; the
design system lives in `lib/shared/widgets/`.

### `lib/core/` — cross-cutting infrastructure

| File | Description |
|---|---|
| [main.dart](apps/mobile/lib/main.dart) | App entry. `runZonedGuarded` + global error hooks, Supabase init, `ProviderScope`, `MaterialApp.router`. |
| [core/env.dart](apps/mobile/lib/core/env.dart) | Build-time config via `--dart-define` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). No secrets baked in. |
| [core/router.dart](apps/mobile/lib/core/router.dart) | `go_router` config with auth-aware + password-recovery redirects. |
| [core/supabase_providers.dart](apps/mobile/lib/core/supabase_providers.dart) | `supabaseClientProvider`, `authStateProvider`, `sessionProvider`, `storageServiceProvider`. |
| [core/theme.dart](apps/mobile/lib/core/theme.dart) | `AppTheme.light()` / `dark()` — Material 3, brand primary violet `#9933FF` (pinned, not seed-derived), Inter font. |
| [core/design_tokens.dart](apps/mobile/lib/core/design_tokens.dart) | `AppSpacing`, `AppRadius`, `AppPalette`, `AppDuration`, `AppElevation`, `AppBreakpoints`. |
| [core/error_handler.dart](apps/mobile/lib/core/error_handler.dart) | Global `AppErrorHandler` — Flutter/zone error hooks + root scaffold-messenger toasts. |
| [core/error_messages.dart](apps/mobile/lib/core/error_messages.dart) | Maps raw exceptions → friendly user-facing strings. |
| [core/auth_recovery.dart](apps/mobile/lib/core/auth_recovery.dart) | Listens to auth state; tracks the password-recovery deep-link flag. |
| [core/push_service.dart](apps/mobile/lib/core/push_service.dart) | FCM bootstrap + token registration + notification handlers. |
| [core/storage_service.dart](apps/mobile/lib/core/storage_service.dart) | Thin wrapper over Supabase Storage (uploads, signed URLs). |

### `lib/shared/widgets/` — design system

Barrel-exported via [widgets.dart](apps/mobile/lib/shared/widgets/widgets.dart). All are **thin wrappers over Material primitives** (so type-based widget finders still resolve). See [shared/widgets/README.md](apps/mobile/lib/shared/widgets/README.md).

`app_card` · `app_list_tile` · `app_stat_tile` · `app_badge` · `app_section_header` · `app_empty_state` · `app_error_view` · `app_loading` · `app_form_field` · `app_snackbar` · `avatar_picker` · `verification_banner`.

### `lib/features/` — feature modules

> Convention: `*_providers.dart` holds Riverpod providers + repository functions; the bare model file (e.g. `student.dart`) holds the plain-class model with a `fromMap` factory. `presentation/` holds pages/sheets/sections.

| Feature | What it does | Notable files |
|---|---|---|
| **auth** | Login (email/phone), signup, forgot/reset password, splash, profile. Holds the **client RBAC mirror**. | [capabilities.dart](apps/mobile/lib/features/auth/data/capabilities.dart), [profile.dart](apps/mobile/lib/features/auth/data/profile.dart), [profile_providers.dart](apps/mobile/lib/features/auth/data/profile_providers.dart), `presentation/login_page.dart`, `signup_page.dart`, `splash_page.dart`, `set_new_password_page.dart` |
| **dashboards** | Role router — picks the right home shell from the profile. | [role_dashboard.dart](apps/mobile/lib/features/dashboards/role_dashboard.dart), `setup_academy_page.dart` |
| **home** | Owner/admin home shells + tabs. | [owner_home_shell.dart](apps/mobile/lib/features/home/owner_home_shell.dart), `home_tab.dart`, `center_admin_home_tab.dart` |
| **academy** | Academy settings (hours, holidays, sports offered). | `academy.dart`, `academy_providers.dart`, `academy_settings_page.dart` |
| **centers** | CRUD for centers (locations) within an academy. | `center.dart`, `center_providers.dart`, `centers_tab.dart`, `center_form_page.dart` |
| **students** | Admin management of student records: list/filter, create/edit, bulk CSV import, documents. | [student.dart](apps/mobile/lib/features/students/data/student.dart), [student_providers.dart](apps/mobile/lib/features/students/data/student_providers.dart), `student_form_page.dart`, `student_bulk_import_page.dart`, `student_documents_section.dart` |
| **coaches** | Admin management of coach records: onboarding, documents, bulk import. | `coach.dart`, `coach_providers.dart`, `coach_document*.dart`, `coach_form_page.dart`, `coach_bulk_import_page.dart` |
| **batches** | Batch CRUD + schedule builder + enrollment. | `batch.dart`, `batch_providers.dart`, `batch_form_page.dart`, `schedule_picker.dart`, `batch_detail_page.dart` |
| **sports** | Sports catalog + per-academy sport settings/picker. | `sport.dart`, `sport_providers.dart`, `sport_picker.dart`, `sports_settings_page.dart` |
| **attendance** | Mark attendance (coach), today's sessions, admin overview. | `attendance.dart`, `attendance_providers.dart`, `attendance_marking_page.dart`, `todays_sessions_page.dart`, `admin_attendance_overview.dart` |
| **performance** | Skill-rubric performance assessments + history/trends. | `performance.dart`, `performance_providers.dart`, `performance_form_page.dart`, `performance_history_page.dart` |
| **billing** | Fees, discounts, invoices, payments, refunds, Razorpay checkout, financial reports. (Largest feature.) | `fee_structure.dart`, `invoice.dart`, `payment.dart`, `discount.dart`, `razorpay_checkout.dart`, `billing_dashboard_page.dart`, `invoice_*_page.dart`, `record_payment_page.dart`, `refund_form_page.dart`, `financial_reports_page.dart` |
| **leads** | Sales funnel: kanban, lead detail/timeline, convert-to-student. | `lead.dart`, `lead_providers.dart`, `leads_kanban_page.dart`, `lead_convert_sheet.dart` |
| **announcements** | Compose + broadcast announcements with targeting. | `announcement.dart`, `announcement_providers.dart`, `announcement_composer_page.dart`, `announcements_page.dart` |
| **chat** | 1:1 + batch group messaging with attachments (Realtime). | `chat.dart`, `attachment.dart`, `chat_providers.dart`, `threads_page.dart`, `thread_detail_page.dart`, `batch_chat_button.dart` |
| **notifications** | In-app notification center + per-channel preferences. | `notification.dart`, `notification_providers.dart`, `notification_center_page.dart`, `notification_preferences_page.dart` |
| **events** | Tournaments/workshops: create, register, results, certificates. | `event.dart`, `event_providers.dart`, `event_form_page.dart`, `event_register_sheet.dart`, `event_results_page.dart` |
| **inventory** | Items, vendors, stock movements (issue/return), low-stock alerts. | `inventory.dart`, `inventory_providers.dart`, `inventory_item_*.dart`, `movement_sheet.dart`, `vendors_page.dart` |
| **analytics** | KPI dashboard + by-sport breakdown. | `analytics_providers.dart`, `sport_breakdown.dart`, `kpi_dashboard_page.dart` |
| **reports** | Custom report builder (pick fields/filters/group-by). | `report_builder.dart`, `report_builder_page.dart` |
| **coach** *(singular)* | The coach's **own** logged-in experience (home shell, batches, students). | `coach_home_shell.dart`, `coach_home_tab.dart`, `coach_batches_tab.dart`, `coach_home_providers.dart` |
| **parent** | The parent's **own** experience: children's attendance/performance/invoices. | `parent_providers.dart`, `parent_home_shell.dart`, `parent_dashboard_tab.dart` |
| **student** *(singular)* | The student's **own** read-only view (sessions, attendance, performance). | `student_home_shell.dart` |
| **users** | Team management + invite-user flow. | `invite_repo.dart`, `invite_user_sheet.dart`, `team_page.dart` |
| **audit** | Audit-log viewer. | `audit_log.dart`, `audit_log_providers.dart`, `audit_log_page.dart` |
| **subscription** | Academy's own SaaS subscription view + upgrade/downgrade. | `subscription_providers.dart`, `subscription_page.dart` |
| **support** | Academy-side support ticket submission. | `support_providers.dart`, `support_page.dart` |
| **super_admin** | Platform-wide module (mobile): academies, plans, global health, tickets. | `super_admin_providers.dart`, `super_admin_home_shell.dart`, `academies_page.dart`, `plans_page.dart`, `global_health_page.dart`, `super_tickets_page.dart` |
| **settings** | App settings tab. | `settings_tab.dart` |

### Mobile tests & platform

| Path | Description |
|---|---|
| [test/](apps/mobile/test/) | Unit/widget tests: `capabilities_test.dart`, `error_messages_test.dart`, `models_test.dart`, `smoke_test.dart`. |
| [integration_test/](apps/mobile/integration_test/) | `app_boot_test.dart` (boot smoke), `login_flows_test.dart`. |
| [pubspec.yaml](apps/mobile/pubspec.yaml) | Deps + Flutter config. |
| [analysis_options.yaml](apps/mobile/analysis_options.yaml) | `very_good_analysis` + strict casts/inference/raw-types. |
| `android/` · `ios/` · `web/` | Platform projects (org `ai.hammad.playhub`); includes `google-services.json` / `GoogleService-Info.plist` for FCM. |

---

## `apps/web-admin/` — Next.js super-admin console

Desktop console for **platform super-admins only**. RLS-respecting by default
(queries ride on the super-admin JWT); service role is a tiny allowlist behind
`assertSuperAdmin()`. See [web-admin/README.md](apps/web-admin/README.md). Dev port **3100**.

### `src/app/` — App Router (RSC) routes

| Path | Description |
|---|---|
| [app/layout.tsx](apps/web-admin/src/app/layout.tsx) · [app/page.tsx](apps/web-admin/src/app/page.tsx) · [globals.css](apps/web-admin/src/app/globals.css) | Root layout, landing redirect, global styles. |
| `app/login/` · `app/forbidden/` · `app/auth/signout/` | Auth surfaces + sign-out route handler. |
| `app/(dashboard)/layout.tsx` | Authenticated shell (sidebar) for all dashboard pages. |
| `app/(dashboard)/health/` | Platform health KPIs + charts. |
| `app/(dashboard)/academies/` | Academies table, detail page, active toggle, invoices panel. |
| `app/(dashboard)/plans/` | Subscription-plan CRUD (`plans-manager.tsx`). |
| `app/(dashboard)/tickets/` | Support tickets table + thread + status/assign actions. |
| `app/(dashboard)/reports/` | Cross-academy report builder. |
| `app/(dashboard)/ops/` | Privileged ops console (service-role-backed). |
| `app/api/ops/find-user/` · `app/api/ops/refresh-analytics/` | Service-role route handlers — each calls `assertSuperAdmin()` first. |

### `src/lib/` — server logic & helpers

| Path | Description |
|---|---|
| [lib/supabase/server.ts](apps/web-admin/src/lib/supabase/server.ts) · `client.ts` · `middleware.ts` | `@supabase/ssr` clients (cookie sessions) for RSC / browser / middleware. |
| [lib/supabase/admin.ts](apps/web-admin/src/lib/supabase/admin.ts) | Service-role client + `assertSuperAdmin()`. `import "server-only"`. |
| [lib/auth.ts](apps/web-admin/src/lib/auth.ts) | `getCurrentUser()` for the signed-in super-admin. |
| `lib/data/*.ts` | **Read** layer (RSC) — `academies`, `billing`, `health`, `plans`, `tickets`. Map snake_case rows → camelCase types. |
| `lib/actions/*.ts` | **Write** layer (`"use server"`) — `academies`, `billing`, `plans`, `tickets`. Return `ActionResult`, call `revalidatePath`. |
| [lib/database.types.ts](apps/web-admin/src/lib/database.types.ts) | Generated Supabase types (`npm run gen:types`). |
| `lib/aggregate.ts` · `csv.ts` · `format.ts` · `download.ts` · `utils.ts` | Pure helpers (unit-tested). |
| [middleware.ts](apps/web-admin/src/middleware.ts) | Route guard — unauth → `/login`, non-super-admin → `/forbidden`. |
| `src/components/` | UI: `app-sidebar`, `data-table`, `charts`, `stat-card`, `page-shell/header`, and primitives under `components/ui/`. |

### Web-admin tests & config

| Path | Description |
|---|---|
| `tests/unit/` | Vitest pure-logic (`aggregate`, `csv`, `format`). |
| `tests/integration/` | Vitest against local Supabase — `rls`, `reads`, `writes`, `capability_matrix`, `ops`, `scenarios`. |
| `tests/e2e/` | Playwright — auth guard, super-admin login, privileged op, rejection. |
| `scripts/create_demo_users.mjs` | Provisions the seeded demo auth users. |
| `next.config.ts` · `tsconfig.json` · `vitest.config.ts` · `playwright.config.ts` · `postcss.config.mjs` · `.eslintrc.json` | Build/test/lint config. |

---

## `supabase/` — backend

### `migrations/` — timestamped SQL (append-only, applied in order)

> Naming: `YYYYMMDDHHMMSS_description.sql`. Every table ships with RLS in the same migration. Grouped by theme below.

| Theme | Migrations |
|---|---|
| **Foundation** (enums, tenancy, users, RLS helpers, auth trigger) | `…000000_init_foundation`, `…000100_relax_users_academy_check`, `…000200_signup_bootstrap`, `…000300_extend_tenancy`, `20260502…_tighten_users_rls` |
| **Core entities** (students, coaches, batches, documents, storage, audit) | `…000400_students`, `…000500_coaches`, `…000600_batches`, `…000700_storage_avatars`, `…000800_student_documents`, `20260502…_coach_documents`, `…_academy_hours_holidays`, `…_transfer_enrollment`, `…_audit_logs` |
| **Daily ops** (attendance, performance, media, summary views) | `20260503…_attendance`, `…_performance`, `…_performance_media_bucket`, `…_attendance_performance_views` |
| **Money** (fees, invoices, payments, late-fee, discounts, bulk assign) | `20260504…_fees`, `…_invoices`, `…_payments`, `20260506…_simplify_late_fee_policy`, `…_drop_batch_fees_add_bulk_assign`, `…_batch_fee_assignments`, `…_discounts`, `…_drop_center_capacity` |
| **Engagement** (parent links, leads, announcements, messaging, notifications, invites) | `20260508…_parent_links`, `…_leads`, `…_announcements`, `…_messaging`, `…_notifications`, `…_chat_attachments_bucket`, `…_convert_lead_rpc`, `…_invite_user_metadata`, `…_invite_must_change_password` |
| **Growth** (events, inventory, SaaS billing, tickets, analytics views, cron) | `20260509…_events`, `…_inventory`, `…_saas_billing`, `…_support_tickets`, `…_center_narrowed_rls`, `…_academy_subscription_autocreate`, `…_analytics_views`, `20260510…_cron_schedules` |
| **Sports & profile** | `20260510…_sports_catalog`, `…_sports_cleanup`, `20260511…_center_sports`, `…_self_profile_photo` |
| **RBAC matrix** | `20260527…_role_capabilities`, `…_role_capabilities_secondary` — the authoritative role→capability matrix mirrored client-side by `capabilities.dart`. |

### `functions/` — Deno edge functions

**Shared** ([functions/_shared/](supabase/functions/_shared/)): `cors.ts` (CORS + `authoriseCron`), `razorpay.ts` (HMAC verify), `billing.ts`, `schedule.ts`, `email.ts` (Gmail SMTP), `fcm.ts` (push), `pdf.ts`. Several have co-located `*.test.ts` (Deno tests).

| Function | Trigger | Description |
|---|---|---|
| [invite-user](supabase/functions/invite-user/index.ts) | client | Creates an auth user + profile (must-change-password). |
| [create-razorpay-order](supabase/functions/create-razorpay-order/index.ts) | client | Creates a Razorpay order, returns key + order id. |
| [razorpay-webhook](supabase/functions/razorpay-webhook/index.ts) | webhook | Verifies HMAC, records `payment.captured/failed`, idempotent via unique event id. |
| [process-refund](supabase/functions/process-refund/index.ts) | client | Razorpay refund API. |
| [public-lead-form](supabase/functions/public-lead-form/index.ts) | public (no auth) | Website-embed lead capture. |
| [convert-lead-to-student](supabase/functions/convert-lead-to-student/index.ts) | client | Atomic lead→student conversion. |
| [send-announcement](supabase/functions/send-announcement/index.ts) | client | Fan-out to FCM + email + in-app. |
| [broadcast-message](supabase/functions/broadcast-message/index.ts) | client | Batch group message broadcast. |
| [generate-invoice-pdf](supabase/functions/generate-invoice-pdf/index.ts) | client | Invoice PDF → signed URL. |
| [generate-certificate-pdf](supabase/functions/generate-certificate-pdf/index.ts) | client | Event certificate PDF. |
| [attendance-report-pdf](supabase/functions/attendance-report-pdf/index.ts) | client | Attendance report PDF. |
| [attendance-aggregate](supabase/functions/attendance-aggregate/index.ts) | cron | Refresh attendance materialized views. |
| [analytics-aggregations](supabase/functions/analytics-aggregations/index.ts) | cron | Refresh analytics views. |
| [auto-mark-absent](supabase/functions/auto-mark-absent/index.ts) | cron | Mark absent after session end. |
| [low-attendance-alert](supabase/functions/low-attendance-alert/index.ts) | cron | Alert on <60% attendance. |
| [lead-followup-reminder](supabase/functions/lead-followup-reminder/index.ts) | cron | Lead follow-up reminders. |
| [mark-overdue](supabase/functions/mark-overdue/index.ts) | cron | Mark overdue invoices + late fees. |
| [recur-invoice-generation](supabase/functions/recur-invoice-generation/index.ts) | cron | Generate next-period invoices. |
| [recur-saas-billing](supabase/functions/recur-saas-billing/index.ts) | cron | Charge academies on renewal. |
| [subscription-grace-period-check](supabase/functions/subscription-grace-period-check/index.ts) | cron | Suspend overdue academies. |

### `tests/`, seed & config

| Path | Description |
|---|---|
| [tests/rls_tenancy.sql](supabase/tests/rls_tenancy.sql) | pgTAP — cross-tenant isolation. |
| [tests/rls_capabilities.sql](supabase/tests/rls_capabilities.sql) | pgTAP — role-capability matrix. |
| [tests/rls_super_admin.sql](supabase/tests/rls_super_admin.sql) | pgTAP — super-admin cross-tenant contract (web-admin depends on this). |
| [tests/functions_and_triggers.sql](supabase/tests/functions_and_triggers.sql) | pgTAP — functions/triggers. |
| [seed.sql](supabase/seed.sql) | Demo-academy seed data. |
| [wipe.sql](supabase/wipe.sql) | Surgical wipe (preserves schema/cron/vault/storage/catalog). |
| [config.toml](supabase/config.toml) | Local Supabase config (Postgres 17 local, ports, auth). |

---

## `scripts/` and `.github/`

| Path | Description |
|---|---|
| [scripts/gen_students_csv.sh](scripts/gen_students_csv.sh) | Generate a students CSV for bulk-import testing. |
| [.github/workflows/mobile.yml](.github/workflows/mobile.yml) | Flutter analyze + test + integration smoke on `apps/mobile/**`. |
| [.github/workflows/supabase.yml](.github/workflows/supabase.yml) | Start local Supabase, apply migrations, run pgTAP suite. |
| [.github/workflows/web-admin.yml](.github/workflows/web-admin.yml) | Web-admin lint/typecheck/test. |
| [.github/workflows/functions.yml](.github/workflows/functions.yml) | Edge-function (Deno) tests. |
