# PlayHub — Complete Development Plan

**Owner:** hammad@ghostmap.ai
**Created:** 2026-05-01
**Target v1.0 launch:** ~12.5 weeks from start (solo-dev pace)
**Market:** India-first; INR, Asia/Kolkata, +91 phone codes

---

## 1. Locked Stack

### Mobile (Flutter, iOS + Android)
| Concern | Choice |
|---|---|
| Framework | Flutter 3.41 stable |
| State | Riverpod 2.x |
| Routing | go_router |
| Models / codegen | freezed + json_serializable |
| Backend SDK | supabase_flutter |
| Local DB / offline | drift (SQLite) |
| Secure storage | flutter_secure_storage |
| Push | firebase_messaging (FCM client only) |
| Biometric | local_auth |
| QR / Camera | mobile_scanner, image_picker |
| Charts | fl_chart |
| PDF | pdf, printing |
| i18n | intl + ARB files |
| Responsive | flutter_screenutil |
| Forms | flutter_form_builder + form_builder_validators |
| Razorpay | razorpay_flutter |

### Backend (Supabase, single infra)
| Service | Use |
|---|---|
| Postgres 16 | Primary DB, RLS-enforced multi-tenancy |
| Supabase Auth | Email + phone OTP (via MSG91 SMTP relay) |
| Supabase Storage | Avatars, documents, media (RLS on buckets) |
| Supabase Realtime | Chat, live attendance, announcement push |
| Edge Functions (Deno) | Webhooks, third-party calls, cron jobs |
| Supabase Vault | Secrets storage |

### External services (paid only when revenue scales)
| Service | Use | Free tier? |
|---|---|---|
| Twilio (via Supabase Auth) | SMS / phone OTP | Pay-per-use; ~$0.0083/SMS to India + DLT fees |
| Razorpay | Payments (UPI/cards/netbanking) | Free integration, 2% per txn |
| FCM | Push notifications | Unlimited free |
| Gmail SMTP | Transactional email (v1) | Free, **500/day cap** |
| Sentry | Error tracking | 5K events/mo free |
| GitHub Actions | CI/CD | 2K min/mo free |
| Vercel | Future Next.js admin (v2.0) | Hobby free, Pro $20/mo |

> **Email migration trigger:** when daily volume approaches 500, migrate to AWS SES (~$0.10/1K emails) or Resend Pro. Plan for v1.2.

### Architecture
```
Flutter (iOS/Android)
    │
    ├──► supabase_flutter SDK ──► Supabase (Auth + DB + Storage + Realtime)
    │                                    │
    │                                    ├─► Auth → Twilio (phone OTP, native)
    │                                    │        Gmail SMTP (auth emails, custom SMTP)
    │                                    │
    │                                    └─► Edge Functions ──► Razorpay (payments)
    │                                                          ├─► FCM (push)
    │                                                          └─► Gmail SMTP (transactional email)
    └──► firebase_messaging (push receiver only)
```

---

## 2. Pre-Sprint Setup (Day 0–2)

### Account creation
- [ ] GitHub repo: `playhub` (private monorepo)
- [ ] Supabase project (free tier, region: Mumbai/Singapore)
- [ ] Razorpay test account (start KYC immediately — takes ~3 days)
- [ ] Twilio account + Indian sender / DLT registration via Twilio (5–10 days; blocks phone OTP for Sprint 0). Configure in **Supabase Dashboard → Auth → Phone Auth → Provider = Twilio**.
- [ ] Gmail account dedicated for app (e.g. `noreply@playhub.app` Gmail) + **App Password** (requires 2FA on the account). Configure in **Supabase Dashboard → Auth → SMTP Settings**:
  - Host: `smtp.gmail.com`, Port: `465` (SSL) or `587` (TLS)
  - User: full Gmail address, Password: 16-char App Password
  - Sender: matches Gmail address (Gmail SMTP rewrites otherwise)
- [ ] Sentry org + 2 projects (mobile, edge)
- [ ] FCM project (Firebase console; messaging only, no other Firebase services)
- [ ] Apple Developer ($99/yr) — defer until Sprint 5
- [ ] Google Play Console ($25 one-time) — before Sprint 6 internal track

### Local toolchain
- [ ] Android Studio + Android SDK
- [ ] Xcode + CocoaPods (`sudo xcodebuild -runFirstLaunch`)
- [ ] `flutter doctor` clean
- [ ] Supabase CLI (`brew install supabase/tap/supabase`)
- [ ] Deno (`brew install deno`) for Edge Function dev
- [ ] FlutterFire CLI

### Repo structure
```
playhub/
├── apps/
│   ├── mobile/                    # Flutter app
│   └── (web-admin/ added v2.0)
├── supabase/
│   ├── migrations/                # SQL migrations
│   ├── functions/                 # Edge Functions (Deno)
│   ├── seed.sql
│   └── tests/                     # pgTAP RLS tests
├── packages/
│   └── shared-types/              # JSON schemas → Dart + TS
├── .github/workflows/
└── PLAN.md
```

---

## 3. Sprint Plan (12.5 weeks total)

> **Definition of Done (every sprint):**
> All migrations applied to staging · RLS tests pass · No P0/P1 bugs · Demo-able to a non-technical person · Release notes drafted · Coverage ≥70% on new code.

---

### Sprint 0 — Foundation (1.5 weeks) → v0.1

**Goal:** Auth works end-to-end. Empty role-specific dashboards.

**Database**
- `users` (id, email, phone, first_name, last_name, role enum, academy_id, center_id, profile_photo, is_active, must_change_password, preferences jsonb, timestamps)
- `academies` (minimal — id, name, owner_id, status, timestamps)
- `centers` (minimal)
- `role` enum: super_admin, academy_owner, academy_admin, center_admin, head_coach, coach, trainer, parent, student
- RLS helper functions: `current_user_id()`, `current_user_academy_id()`, `current_user_role()`, `is_super_admin()`, `has_admin_or_higher()`, `has_role(text)`
- RLS policies on `users`, `academies`, `centers`
- Trigger: on `auth.users` insert → create `public.users` row

**Edge Functions**
- `signup-bootstrap` — runs after auth signup, sets up academy if owner
- (Phone OTP handled natively by Supabase Auth → Twilio; no custom function needed)
- (Auth emails — verification, magic link, password reset — handled natively by Supabase Auth → Gmail SMTP)
- `send-transactional-email` — generic helper for non-auth emails (receipts, reminders) using Gmail SMTP via Deno SMTP client; rate-limited to stay under 500/day cap

**Flutter**
- Project init, all deps, lint config (very_good_analysis)
- Riverpod provider tree
- go_router with auth-aware redirects
- Material 3 theme (light + dark)
- Screens: splash, login (email/phone toggle), signup, OTP entry, email verify, forgot password
- Phone OTP via `supabase.auth.signInWithOtp(phone: ...)` (Supabase routes to Twilio)
- Email auth via `supabase.auth.signInWithPassword` / `signInWithOtp(email)` / `resetPasswordForEmail` (Supabase routes through Gmail SMTP)
- 9 stub dashboards (one per role), routed by role
- Profile screen (basic)
- Logout

**Testing**
- Auth integration test (login → dashboard)
- pgTAP: tenant A user cannot SELECT tenant B users

**Deliverable:** v0.1 — login works, you see the right dashboard.

---

### Sprint 1 — Tenancy & Core Entities (2 weeks) → v0.3

**Goal:** Full CRUD on academies, centers, students, coaches, batches.

**Database**
- `academies` (extend: logo, contact, address, sports_offered, subscription, etc.)
- `centers` (full)
- `students` (full per SRD §7.1)
- `coaches` (full)
- `batches` (full, with schedule jsonb)
- `batch_enrollments` (junction)
- `student_documents`, `coach_documents`
- `audit_logs` (id, user_id, academy_id, action, entity_type, entity_id, before jsonb, after jsonb, created_at)
- RLS on all tables
- Composite indexes: `(academy_id, …)` patterns
- Trigger: audit log writer for sensitive ops

**Storage buckets**
- `avatars` (public read, owner write)
- `student_documents` (private, RLS)
- `coach_documents` (private, RLS)
- `academy_assets` (public, owner-only write)

**Edge Functions**
- `generate-student-id` — atomic counter per academy
- `bulk-import-students` — CSV → batch insert with validation
- `bulk-import-coaches`

**Flutter**
- Academy settings (FR-SET-001): logo, contact, sports, holiday calendar, hours
- Centers: list, create, detail, edit, soft delete
- Students: list (search/filter/sort), create wizard, detail, edit, document upload, photo capture, status mgmt
- Coaches: list, onboarding wizard (qualifications, certifications, salary), detail, edit
- Batches: list, create (schedule builder UI), detail, edit, capacity meter
- Batch enrollment: add students, transfer, waitlist
- Reusable widgets: SearchableList, FilterDrawer, BulkActionBar, FormStepper

**Testing**
- E2E: owner → admin → student → batch → coach
- RLS: every table tested for cross-tenant isolation
- Bulk import: 1000-row CSV happy path

**Deliverable:** v0.3 — academy operational; can onboard students/coaches/batches.

---

### Sprint 2 — Daily Operations: Attendance + Performance (2 weeks) → v0.5

**Goal:** Coaches mark attendance and record performance. Parents/students see results live.

**Database**
- `attendance_records` (academy_id, student_id, batch_id, coach_id, date, status, check_in_time, check_out_time, notes, marked_by, method, …)
- `performance_assessments` (header)
- `performance_skills` (line items: name, score 1–10, notes)
- `performance_media` (urls, type)
- Materialized view: `student_attendance_summary` (refreshed nightly)
- Materialized view: `student_performance_trend`
- RLS scoped by academy, with role-based read (coach: own batches; parent: own children; admin: all in academy)

**Storage**
- `performance_media` bucket (private, RLS)

**Edge Functions**
- `attendance-aggregate` (cron, refreshes mat views)
- `low-attendance-alert` (cron daily, FCM + email if <60% over 30 days)
- `attendance-report-pdf` (on-demand, returns signed URL)
- `auto-mark-absent` (cron after session end times)

**Flutter**
- Coach: today's batches view (chronological)
- Coach: attendance screen — bulk mark all present, individual toggle, late status, notes
- Coach: edit attendance within 24h
- Coach: performance recording with skill rubric (configurable per sport)
- Coach: upload photo/video with on-device compression
- Parent: child attendance calendar view + percentage
- Parent: child performance dashboard with progress charts
- Student: own dashboard mirror (read-only)
- **Drift offline queue:** attendance + performance writes work offline; sync on reconnect with last-write-wins
- Sync indicator widget
- Charts: attendance %, skill progression over time, peer comparison (anonymized)

**Realtime**
- Admin dashboard subscribes to attendance inserts for live ops view

**Deliverable:** v0.5 — full daily ops loop. Coach can work fully offline.

---

### Sprint 3 — Money: Fees + Payments (2 weeks) → v0.7

**Goal:** Razorpay live. Invoices auto-generate. Parents pay. Admins reconcile.

**Database**
- `fee_structures` (type: monthly/quarterly/annual/one-time, sport, batch, base_amount, tax_pct, late_fee_pct, …)
- `student_fee_assignments` (which fee structure applies to which student)
- `invoices` (academy_id, student_id, invoice_number, amount, amount_paid, status, due_date, …)
- `invoice_line_items`
- `payments` (full per SRD §7.1)
- `payment_attempts` (each Razorpay order attempt)
- `refunds`
- Sequence per academy for invoice numbers

**Edge Functions**
- `create-razorpay-order` — creates order, returns key + order_id to client
- `razorpay-webhook` — verifies signature (HMAC-SHA256), updates payment + invoice atomically
- `generate-invoice-pdf` — Deno + pdf-lib, signed URL
- `send-payment-reminder` (cron daily)
- `mark-overdue` (cron daily, applies late fee)
- `recur-invoice-generation` (cron daily, generates next month's invoices)
- `process-refund` — Razorpay refund API
- `payment-confirmation-email` (on payment success)

**Flutter**
- Admin: fee structure CRUD
- Admin: assign fee to student/batch (bulk)
- Admin: invoice list with filters (status, date, batch, defaulter)
- Admin: record manual payment (cash/cheque)
- Admin: refund flow with reason + approval
- Admin: financial reports (revenue daily/monthly/yearly, outstanding dues, by sport, by center)
- Parent: outstanding dues card on dashboard
- Parent: pay via Razorpay (razorpay_flutter SDK)
- Parent: payment history + receipt download
- PDF receipts (auto on success)

**Testing**
- E2E with Razorpay test keys: order → pay → webhook → invoice closed
- Refund flow
- Webhook signature verification (negative tests)
- Concurrency: two payments same invoice → only one succeeds

**Deliverable:** v0.7 — money flows end-to-end. Razorpay test mode → production switch.

---

### Sprint 4 — Engagement: Leads + Communication (1.5 weeks) → v0.8

**Goal:** Lead funnel + chat + announcements + notifications.

**Database**
- `leads` (full)
- `lead_activities` (status changes, notes, calls logged)
- `announcements` (target_roles, target_batches, target_centers, scheduled_for)
- `announcement_recipients` (read receipts)
- `message_threads` (1:1 or group)
- `messages` (with attachments)
- `notification_preferences` (per user, per channel)
- `notifications` (in-app feed)

**Edge Functions**
- `public-lead-form` — no-auth endpoint, captcha-protected, for website embed
- `lead-followup-reminder` (cron)
- `send-announcement` — fans out to FCM + email + in-app
- `broadcast-message`
- `convert-lead-to-student` — atomic transaction (creates student, marks lead converted)

**Flutter**
- Admin: leads kanban (new → contacted → interested → trial → converted/lost)
- Admin: lead detail with activity timeline
- Admin: convert lead one-click
- Admin: trial session scheduling
- Coach/Parent/Student: 1:1 chat
- Batch group chat (parents + coach)
- Announcement composer (admin/owner) with role/batch/center targeting
- Announcement feed across all roles
- In-app notification center
- Push notification handlers (foreground + background + tap-to-route)
- Notification preferences screen

**Realtime**
- Chat messages stream
- Announcement broadcast
- Notification feed

**Deliverable:** v0.8 — funnel + comms loops live.

---

### Sprint 5 — Growth: Events + Inventory + Analytics + SaaS Billing (2 weeks) → v0.9

**Goal:** Remaining features for v1 launch + super-admin module.

**Database**
- `events` (tournaments, workshops)
- `event_registrations`
- `event_results`
- `inventory_items`
- `inventory_categories`
- `inventory_movements` (issue/return)
- `vendors`
- `subscription_plans` (Basic/Pro/Enterprise)
- `academy_subscriptions`
- `saas_invoices`
- `saas_payments`

**Edge Functions**
- `recur-saas-billing` (cron, charges academies on renewal)
- `generate-certificate-pdf` (event participation)
- `analytics-aggregations` (refresh materialized views)
- `subscription-grace-period-check` (cron, suspends overdue academies)

**Flutter**
- Events: list, create, register, view, results entry
- Certificate generation/download
- Event calendar with filters
- Inventory: items, categories, issue/return tracking
- Inventory: low stock alerts
- Inventory: reports (stock summary, movement history)
- Custom report builder (basic: pick fields, filters, group by)
- Enhanced role dashboards with KPIs:
  - Owner: revenue trend, growth metrics, financial overview
  - Admin: enrollment, payment collection, lead conversion, batch utilization
  - Center Admin: center-specific metrics
  - Head Coach: assigned batches, performance overview
- **Super Admin module (separate routes):**
  - All academies list
  - Subscription plans CRUD
  - Global revenue + signups
  - System health
  - Support tickets (basic)
- Academy owner: subscription mgmt + upgrade/downgrade flow

**Deliverable:** v0.9 — feature-complete for v1.0 SRD coverage (minus deferred items).

---

### Sprint 6 — Polish + Launch (1.5 weeks) → v1.0

**Goal:** App stores, beta academies onboarded.

- Hindi localization (ARB files complete)
- Accessibility audit: semantics labels, contrast, screen reader paths
- Performance profiling: app launch <3s, list scroll 60fps
- Store assets: screenshots (5 devices each), descriptions, keywords
- Privacy policy + terms of service (legal review)
- TestFlight build + internal testers
- Play Store internal testing track
- Sentry source maps + crash reporting verified
- Load testing: k6 against Supabase (1000 concurrent)
- Security review:
  - Every RLS policy double-checked
  - Storage bucket policies
  - Edge Function input validation
  - Razorpay webhook replay protection
- Beta with 2 friendly academies (real students/payments)

**Deliverable:** v1.0 — public launch on App Store + Play Store.

---

## 4. Version Roadmap

### v0.x — Pre-launch (Sprint 0–6)
| Version | End of Sprint | Capability |
|---|---|---|
| v0.1 | 0 | Auth + role dashboards |
| v0.3 | 1 | Tenancy + core CRUD |
| v0.5 | 2 | Daily ops (attendance + performance) |
| v0.7 | 3 | Payments live |
| v0.8 | 4 | Leads + comms |
| v0.9 | 5 | Feature-complete |
| **v1.0** | **6** | **Public launch** |

### v1.0 Coverage vs SRD
**Included:** All "High" priority FRs, most "Medium" priority FRs.
**Deferred:**
- FR-ATT-002 Biometric attendance (needs hardware) → v1.1
- FR-ATT-004 Auto attendance fee adjustment → v1.1
- FR-EVENT-002 iCal export → v1.1
- FR-ANALYTICS-003 AI insights → v2.1
- FR-STU-004 Digital ID cards (low) → v1.2
- Web admin → v2.0
- Full COPPA parental consent flow → v1.2

### v1.1 — Hardening (4 weeks post-launch)
- Bug fixes from production
- **Biometric attendance** via on-device ML Kit face recognition
- Improved offline sync (operation log, conflict UI)
- iCal calendar export
- Performance fixes from real metrics
- Auto attendance-based fee adjustments

### v1.2 — Scale Prep (6 weeks)
- Migrate to Supabase Pro ($25/mo)
- Vercel Pro ($20/mo) for compliant commercial use (when Edge Function load grows or web admin lands)
- **Migrate transactional email off Gmail SMTP → AWS SES** (~$0.10/1K) once daily volume crosses ~300/day. Auth emails can stay on Gmail until volume forces a switch.
- PgBouncer tuning + connection pooling
- Materialized view refresh schedule optimization
- In-Edge-Function caching
- COPPA full flow (parental consent gates for under-13)
- Tamil, Telugu, Marathi localization
- Digital student ID cards with QR
- Audit log retention policies (1yr default, exportable)

### v2.0 — Web Admin (8 weeks)
- **Next.js 15 web admin app on Vercel**
  - Same Supabase backend (SSR with service role + RLS bypass for admin queries via server actions)
  - Desktop-optimized: large data tables, bulk operations, keyboard shortcuts
  - Excel import/export
  - Advanced report builder with saved templates
  - Email campaign tool
  - Super admin power features
- Coach/admin laptops can use web instead of mobile

### v2.1 — AI Features (4 weeks)
- Churn prediction (Gemini API or self-hosted XGBoost)
- Performance forecasting per student
- Anomaly detection (sudden attendance drop, payment risk)
- Per-student improvement recommendations
- Batch performance correlation analysis
- Revenue optimization suggestions

### v2.2 — Multi-region & Compliance (6 weeks)
- Data residency option (Supabase India region)
- DPDP Act compliance (India)
- Enhanced audit + reporting for enterprise customers
- SSO (Google/Microsoft) for academy staff
- Custom domain per academy (white-label prep)

### v3.0 — Platform (12+ weeks, open-ended)
- Public REST API for academy partners
- Webhook system (academies subscribe to their own events)
- White-label theming per academy
- Marketplace: coaches, equipment, training programs
- Advanced tournament management (brackets, live scoring)
- Live streaming integration (sessions broadcast to parents)
- Wearables integration (Apple Watch / Mi Band heart rate, GPS)
- Video performance analysis with AI coaching cues

---

## 5. Cross-Cutting Concerns

### Security
- RLS on every table from day 1
- Storage bucket RLS on every bucket
- Edge Functions validate JWT on every protected route
- Service role key never leaves Supabase Vault / Edge Function env
- Razorpay webhook: HMAC verification + idempotency key + replay window
- Audit log on: payments, role changes, deletions, subscription changes
- TLS 1.3 (Supabase + Vercel default)
- Quarterly security review post-launch
- pgTAP tests for every RLS policy in CI
- Pen-test before v1.0 launch (or use Supabase's checklist)

### Testing strategy
- **Flutter:**
  - Unit: providers, repos, validators (target 70% on new code)
  - Widget: critical flows (login, payment, attendance marking)
  - Integration: end-to-end auth + payment with mocked Razorpay
- **Backend:**
  - SQL function tests
  - pgTAP RLS tests (assert tenant A cannot read tenant B for every table)
  - Edge Function unit tests (Deno test)
- **E2E:** Maestro for mobile critical paths

### CI/CD (GitHub Actions)
- **On PR:**
  - Flutter: lint, analyze, test, build APK debug
  - Supabase: SQL lint, RLS tests, Edge Function tests
- **On merge to main:**
  - Apply migrations to staging
  - Deploy Edge Functions
  - Build APK + IPA, upload to internal track / TestFlight
- **On release tag:**
  - Apply migrations to production (after manual approval gate)
  - Promote builds to production tracks
- Fastlane for store metadata mgmt

### Monitoring
- Sentry: Flutter + Edge Functions
- Supabase logs: auth, db, realtime, edge fn
- Custom dashboard via SQL views: signups, payments, errors, active sessions
- Better Stack uptime checks on critical Edge Functions
- Razorpay webhook delivery monitoring

### Localization
- ARB files structured from Sprint 0
- v1.0: English only (Hindi strings ready, untranslated)
- v1.1: Hindi launched
- v1.2: Tamil, Telugu, Marathi
- Right-to-left: not needed
- Number formatting: INR currency, Indian digit grouping (1,00,000)

### Compliance
- v1.0: GDPR-ready (consent capture, export endpoint, hard-delete after 30-day soft delete)
- v1.1: COPPA partial (age gate)
- v1.2: COPPA full (parental consent for under-13)
- v2.2: DPDP Act (India) full compliance + data residency

### Performance budgets
- App launch: <3s cold, <1s warm
- API p95: <500ms
- Page transitions: <200ms
- List scroll: 60fps with 1000 items (pagination after that)
- App size: <50MB

---

## 6. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Twilio India DLT registration delay | High | Medium | Start Day 0; email-OTP fallback in dev (skips Twilio entirely) |
| Gmail SMTP 500/day cap hit | Medium | Medium | Throttle non-critical emails; auto-migrate to AWS SES at threshold |
| Gmail flags app as spam / locks account | Low | High | Use dedicated Gmail (not personal); SPF/DKIM via Google Workspace if scaling |
| Razorpay KYC delay | Medium | High | Start Day 0; test mode meanwhile |
| Apple App Store rejection | Medium | High | Strict guideline adherence; TestFlight thoroughly first |
| RLS policy bug → cross-tenant leak | Low | Critical | Automated RLS tests in CI; pen-test before launch |
| Supabase free tier limits hit | Medium | Medium | Monitor; upgrade to Pro at first paying customer |
| Solo-dev burnout / timeline slip | Medium | High | Don't compress; cut scope before extending hours |
| Push notification delivery issues | Low | Medium | FCM is reliable; email + in-app fallbacks |
| Razorpay webhook missed/replayed | Medium | High | Idempotency keys + reconciliation cron |
| Offline sync conflict on attendance | Medium | Medium | Last-write-wins v1; conflict UI v1.1 |
| Bulk import corrupts data | Low | High | Dry-run mode + transaction wrapper + audit log |

---

## 7. Schedule Summary

| Sprint | Weeks | Cumulative | Version | Key feature |
|---|---|---|---|---|
| 0 | 1.5 | 1.5 | v0.1 | Foundation |
| 1 | 2.0 | 3.5 | v0.3 | Tenancy + entities |
| 2 | 2.0 | 5.5 | v0.5 | Operations |
| 3 | 2.0 | 7.5 | v0.7 | Money |
| 4 | 1.5 | 9.0 | v0.8 | Engagement |
| 5 | 2.0 | 11.0 | v0.9 | Growth |
| 6 | 1.5 | 12.5 | **v1.0** | **Launch** |

**v1.0 launch:** ~3 months from kick-off at solo-dev pace.

---

## 8. Out-of-Scope (Explicit "Not Doing")

- Self-hosted Supabase (use managed)
- Custom Node API middle tier (Edge Functions handle all backend logic)
- Native iOS/Android (Flutter only)
- Offline payments (online only)
- Cryptocurrency
- Video calls (only async media)
- LMS / course content delivery (this is academy ops, not e-learning)
- Hardware sales / equipment marketplace (post-v3)
- Coach hiring marketplace (post-v3)

---

## 9. Open Decisions

1. **Sport-specific skill rubrics:** ship configurable per academy, OR ship 5 default sports (cricket, football, badminton, swimming, basketball)? — recommend default-then-customize
2. **Trainer role permissions:** "with approval" workflow needed in v1.0, or defer? — recommend defer to v1.1
3. **Multi-academy users:** can a coach work for two academies? — recommend NO in v1.0 (one user = one academy)
4. **Free trial period for SaaS:** 14 days or 30 days? — recommend 14
5. **Payment failure retry:** auto-retry 3x or manual? — recommend auto 3x with backoff

---

## 10. Sprint 0 Kick-Off Checklist

When you say go:
- [ ] Create GitHub repo, push monorepo skeleton
- [ ] `flutter create` mobile app with org `ai.ghostmap.playhub`
- [ ] Init Supabase project, apply auth config
- [ ] Twilio account + Indian sender / DLT registration (CRITICAL — blocks phone OTP at Sprint 0 end). Configure in Supabase Auth → Phone provider.
- [ ] Gmail App Password generated; configured in Supabase Auth → SMTP settings.
- [ ] Razorpay test keys provisioned
- [ ] Sentry + FCM projects ready
- [ ] First migration: `users` + `academies` + `centers` + `role` enum + RLS helpers
- [ ] First Edge Function: `signup-bootstrap`
- [ ] Flutter: `main.dart`, theme, router, auth screens, 9 stub dashboards
- [ ] CI green on PR
- [ ] Tag v0.1
