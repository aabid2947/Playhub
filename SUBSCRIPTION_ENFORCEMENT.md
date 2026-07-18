# Subscription Enforcement — restrict actions after the 14-day trial

**Status:** Planned (not yet implemented). **Decided:** 2026-06-27.
**Scope decisions (locked):**
- **Freeze model = read-only freeze.** When an academy is suspended (trial expired & unpaid, or
  SaaS invoice overdue), block ALL create/edit/manage writes. Keep open: all reads, raising a
  support ticket, and the pay-to-unlock path.
- **Recovery = super-admin reactivate + mobile paywall.** Ship enforcement + a paywall screen now;
  super-admin records the SaaS payment (auto-reactivates) or clicks Reactivate. Owner in-app
  self-serve SaaS checkout is a **fast-follow** (Phase 6), not this release.

This is the "v1.1 enforcement layer" the SaaS billing code explicitly deferred
(`20260509000200_saas_billing.sql:42` — *"Soft caps (UI hints; real enforcement TBD in v1.1)"*).

---

## 0. Why this is more than a flag flip (research findings)

1. **Trial is already 14 days** — `academies.trial_ends_at default (now() + interval '14 days')`
   (`supabase/migrations/20260501000000_init_foundation.sql:37`). No duration change needed. (Clean up
   the stale `'1 month'` fallback in `ensure_academy_subscription` / `saas_billing` for consistency.)
2. **A trial can never get suspended today.** `recur-saas-billing` skips `trial` subscriptions and
   there is **no `trial → active` conversion** anywhere; the suspend cron keys off overdue
   `saas_invoices`, but trials never get an invoice. ⇒ we must add a **trial-expiry path**.
3. **No reactivation path exists.** Nothing flips `suspended → active` / `is_active → true` after a
   SaaS payment (verified across webhooks, triggers, web-admin `actions/billing.ts` `recordSaasPayment`,
   `actions/academies.ts` `setAcademyActive`). ⇒ recovery loop is mandatory, not optional.

**Real status enum** (`init_foundation.sql:23-29`): `trial · active · past_due · suspended · cancelled`.
The mobile `AcademySubscription.status` list (`trialing/unpaid/paused`, missing `suspended`/`trial`) is
**wrong** and is fixed in Phase 5.

## Target lifecycle

```
new academy → trial (14d)
   ├─ pays                    → active ⇄ past_due (7–14d grace; still works, banner warns)
   └─ trial expires, unpaid   → SUSPENDED   ← all management writes blocked
SUSPENDED → (SaaS payment recorded → auto-reactivate │ super-admin Reactivate) → active
```

---

## 1. Core mechanism — ONE RLS gate (invariant #1)

Single source of truth for "may this academy write?". Immediate trial-expiry enforcement (no cron lag),
still allows the grace window, bypasses for super-admin, one PK lookup.

```sql
create or replace function public.academy_writes_allowed()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_super_admin() or exists (
    select 1 from public.academies a
    where a.id = public.current_user_academy_id()
      and a.subscription_status <> 'cancelled'
      and (
        a.subscription_status in ('active','past_due')
        or (a.subscription_status = 'trial'
            and (a.trial_ends_at is null or a.trial_ends_at > now()))
      )
  );
$$;
```

**Do NOT patch** `is_super_admin()` or `current_user_academy_id()` — they are used in READ policies;
patching them would block reads. The gate is added only to WRITE paths.

---

## 2. Phase 1 — Backend enforcement (the bulk)

One new append-only migration. Wire `academy_writes_allowed()` into write policies two ways:

**(a) Patch content-only helper functions** (write-only → safe; verify none appear in a `SELECT`
policy before editing). Add `and public.academy_writes_allowed()`:

| Helper | Defined | Covers |
|---|---|---|
| `can_admin_center_scope` | `20260527000000:67` | students, coaches, leads, inventory_items, finance-content (via delegation), provisioning |
| `can_manage_batches` | `20260527000000:84` | batches, enrollments, events |
| `can_manage_batch_fields` | `20260607000200:59` | batch fields, enrollments |
| `can_mark_attendance` | `20260527000000:117` | attendance_records |
| `can_record_performance` | `20260527000000:137` | performance_assessments/skills/media |
| `can_record_perf_for_assessment` | `20260527000100` | performance skills/media |
| `can_admin_lead` | `20260527000100` | lead_activities |
| `can_staff_batch` | `20260607000300:84` | batch_staff |

**(b) Add `AND academy_writes_allowed()` to content policies that inline `has_admin_or_higher()` or a
role list** (no reusable helper). Drop+recreate each in the migration:

- fee_structures `20260504000000:99-119` · student_fee_assignments `:127-147`
- discount_structures + assignments `20260506000300:125-195`
- announcements `20260508000200:94-112` · message_threads/thread_participants `20260508000300:323-366`
- vendors `20260509000100:181-201` · inventory_categories `:213-233` · inventory_movements `:278-287`
  · inventory_stock `20260614000100`
- center_sports `20260511000000` · academy_sports `20260510000100:96-116` · coach_sports `:143-163`
- parent_links `20260508000000:114-134` · event_registrations/results `20260509000000:227-280`

**Carve-outs — MUST stay open (do not gate):**
- **SaaS payment path** — `saas_payments`/`saas_invoices` are super-admin-only; webhooks are
  service-role → already bypass RLS. Unlock path is structurally un-blockable.
- **Student-payment webhooks** (Razorpay/Paytm) — service-role, bypass RLS → invariant #6 money
  idempotency intact.
- **Support tickets** `20260509000300:81-106` — suspended owner must be able to ask for help. Leave INSERT open.
- **All reads**, notification/message read-receipts, and super_admin.

**pgTAP** (`supabase/tests/rls_subscription_enforcement.sql`): suspended academy owner denied INSERT on
students/coaches/batches/fees/etc.; still allowed reads + support ticket; super_admin + service-role unaffected.

## 3. Phase 2 — 14-day trial-expiry suspension

- **Immediate**: handled by the live check in `academy_writes_allowed()` (writes stop the moment
  `trial_ends_at` passes — no cron lag).
- **Status hygiene** (for UI/badges/reporting): extend `subscription-grace-period-check` (or a new
  `trial-expiry-check`) cron to flip `status='trial' AND trial_ends_at < now()` →
  `suspended` + `is_active=false`. Idempotent, mirrors the existing cron.

## 4. Phase 3 — Reactivation loop (don't strand academies) — build BEFORE flipping enforcement on

- **Auto-reactivate trigger** on `saas_payments` insert: when all the subscription's invoices are
  `paid`/`cancelled` → `academy_subscriptions.status='active'`, `academies.subscription_status='active'`,
  `is_active=true`. New append-only migration.
- **Trial → active conversion**: "start subscription" path that generates the first SaaS invoice so it
  can be paid (trials have no invoice today).
- **Web-admin**: `reactivateSubscription(academyId)` action + **Reactivate** button on the academy
  detail page when suspended (today only `setAcademyActive` exists, which doesn't touch subscription status).

## 5. Phase 4 — Web-admin

Reactivate action + button (Phase 3). Suspended badges already exist. Run `npm run gen:types`.

## 6. Phase 5 — Mobile UX

- **Fix status model** (`features/subscription/data/subscription_providers.dart:6-47`): real enum +
  `isSuspended` / `isActive` / `trialDaysLeft`. `mySubscriptionProvider` already queries
  `academy_subscriptions` — no new query.
- **Paywall gate** in `features/dashboards/role_dashboard.dart`, appended to the existing chain
  (`mustChangePassword → needsAcademySetup → [new] suspended`): owner/admin + suspended → **PaywallPage**
  (renew / contact CTA); other roles + suspended → read-only shell + "academy inactive" banner.
- **Proactive UI gating**: `activeCapabilitiesProvider` returns read-only capabilities when suspended so
  create/edit buttons grey out before a write is attempted (RLS stays the hard backstop).
- **Wire `SubscriptionPage` into the router** (exists, currently unreachable) + a "Renew" CTA.
- **Trial-ending banner** in `features/home/owner_home_shell.dart` (reuse dismissible-banner pattern).
- **Error message** (`core/error_messages.dart:41-44`): on `42501` when `mySubscriptionProvider` is
  suspended → "Your trial has ended — renew to continue" + Renew action (client cross-references known
  status; no custom Postgres error code needed).

## 7. Phase 6 — Owner self-serve SaaS payment (FAST-FOLLOW, not this release)

Extend `create-payment-order` to accept SaaS invoices (Razorpay/Paytm), reuse
`PaymentCheckout.payInvoice(invoiceId, …)` (`features/billing/data/payment_checkout.dart:25`), auto-reactivate
via the Phase 3 trigger. Until then, recovery is super-admin-recorded payment / Reactivate.

---

## Recommended build order (recovery before enforcement, so no one is stranded)

1. ✅ **Migration A** — `academy_writes_allowed()` helper + `'1 month'`→14d fallback fix.
   `20260627000000_subscription_writes_gate.sql`. (No behaviour change yet — gate not wired in.)
2. ◐ **Migration B** — auto-reactivate trigger DONE (`20260627000100_saas_auto_reactivate.sql`).
   Trial→active *billing* conversion (generate first invoice) deferred to step 5/Phase 6 — the
   web-admin Reactivate button (step 3) already covers trial-expired recovery.
3. ✅ **Web-admin** — `reactivateSubscription` action (`lib/actions/billing.ts`) + Reactivate button
   (`academies/[id]/subscription-reactivate.tsx`, shown when suspended). `gen:types` NOT needed
   (no new table/column/enum). Recovery path live.
   - ⚠️ Unverified: `npm run typecheck` not run (node_modules not installed in apps/web-admin).
4. ✅ **Enforcement** — became TWO migrations + a pgTAP test (Phase 1, enforcement now live once applied):
   - `20260627000200_subscription_enforce_writes.sql` — gates 16 write-only capability helpers
     (`can_manage_student/coach_record/coach/batches/batch_fields/enrollment/staff_batch/mark_attendance/
     record_performance/record_perf_for_assessment/upload_student_media/finance/invoice/batch_finance/
     admin_lead/provision_role`). `can_admin_center_scope` left UNGATED (reused in finance reads).
   - `20260627000300_subscription_enforce_policies.sql` — policy-level gate for tables bypassing those
     helpers: students_update (coach branch), leads, inventory_items, fee/discount structures,
     center_sports, academy_sports, vendors, inventory_categories, inventory_movements, parent_links,
     announcements, event_registrations (staff only — parent self-register preserved), event_results.
   - `supabase/tests/rls_subscription_enforcement.sql` — pgTAP: active/trial-ok allow; trial-expired/
     suspended block; reads still work; super_admin overrides. **⚠️ not run here (needs local Supabase/Docker).**
   - Carve-outs left open: saas_* (pay-to-unlock), support tickets, messaging/notifications, parent self-register.
5. ✅ **Cron** — `subscription-grace-period-check` now also suspends lapsed trials (Step 0) and
   reports `trials_suspended`. Live RLS check still does the real-time enforcement.
6. ✅ **Mobile** — `AcademySubscription` gained `writesAllowed`/`isBlocked`/`isTrial`/`trialDaysLeft`/
   `isTrialEndingSoon`; new `PaywallPage`; `RoleDashboard` routes a blocked owner/admin → paywall;
   trial-ending / inactive banner in the owner shell (`_SubscriptionBanner`). `flutter analyze` clean.
   - Deferred polish: broad `activeCapabilitiesProvider` button-greying + a suspension-specific
     `error_messages` string (the paywall covers the owner/admin path; other roles get the generic
     "no permission" until then).
7. ◐ **Verify** — `flutter analyze` clean (mobile). **NOT run (need local Supabase/Docker + npm i):**
   `supabase/tests/rls_subscription_enforcement.sql`, web-admin `typecheck`, and the manual
   suspend→reactivate walkthrough.
8. ✅ **CLAUDE.md change-log entry** added (2026-06-27).

## Ripple & guardrails (per CLAUDE.md)

- Append-only migrations (invariant #5) via `create or replace` / `drop+create policy`.
- **Invariant #3 untouched**: this is a cross-cutting gate, deliberately NOT a new role-capability matrix
  row, so the DB-matrix ↔ `capabilities.dart` mirror pair stays in sync without edits.
- **Invariant #6**: money webhooks bypass RLS → idempotency/verification intact. Manual student-fee
  *recording* by an admin IS blocked under the read-only freeze (accepted consequence; online webhook
  payments still post via service-role).
- Reads never blocked · super_admin always bypasses AND can reactivate (no permanent lockout).
- **Dev safety**: set demo/seed academies to `active` (or a fresh 14-day trial) so `supabase db reset`
  doesn't lock testers out (`seed.sql:338`).
- Schema change → `gen:types` (web-admin) + update the Dart `fromMap`/status model.
