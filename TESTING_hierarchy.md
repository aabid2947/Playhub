# Hierarchy QA — every action, by role

Complete manual test matrix for the org-hierarchy re-architecture. Walk **one
login at a time**, tick each box. All demo logins use password `Demo@1234`.

> **Demo data** (after `seed.sql` + `create_demo_users.mjs`): Center **A** =
> Andheri (most staff), Center **B** = Bandra (the trainer). head_coach = cricket,
> coach = football, trainer = swimming (Center B).

## Legend
- ✅ = should WORK (the UI offers it and the save/read succeeds)
- 🚫 = should be BLOCKED (UI hides it, or the action errors with a permission/center message)
- 🔒 = **already proven by the pgTAP suite** (verify_hierarchy_rls.sql = green) → here you're only checking the **UI surfaces/hides** it correctly, not re-proving RLS
- ⚠️ = known gap (NOT a bug — see "Known gaps" at the bottom)

## Prerequisites (must be true before manual testing)
- [ ] DB on all 9 hierarchy migrations (`verify_hierarchy_rls.sql` → "Success") ✅ done
- [ ] Edge functions deployed: `invite-user`, `convert-lead-to-student`, `ai-insights`
- [ ] App rebuilt/relaunched (`flutter run …`)
- [ ] Demo logins fresh (optional `create_demo_users.mjs --wipe-all-users`)

---

## 1 · academy_owner — `owner@playhubdemo.in`  (sees ALL centers)
**Provisioning**
- [ ] ✅ Settings → Team → Invite: dropdown shows admin/center_admin/head_coach/coach/trainer/parent/student
- [ ] ✅ Invite each of the above succeeds (centre optional)
- [ ] 🚫 No option to invite another `academy_owner`
**Org / records**
- [ ] ✅ Settings → Academy settings (owner-only) is visible & editable
- [ ] ✅ Settings → Subscription visible
- [ ] ✅ Settings → Centers: create / edit a center
- [ ] ✅ Settings → Sports: enable a sport for **any** center
- [ ] ✅ Students / Coaches / Batches: create + edit in **any** center & sport
- [ ] ✅ Enroll a student into any batch
**Sessions / money**
- [ ] ✅ Mark attendance + record performance on any batch
- [ ] ✅ Student → Fees/Discounts: assign; record a payment; **Refund button present** on a payment
- [ ] ✅ Leads / Inventory / Events: create in any center
- [ ] ✅ AI insights on any student
- [ ] ✅ All lists show **both** Center A and Center B rows

## 2 · academy_admin — `admin@playhubdemo.in`  (sees ALL centers)
- [ ] ✅ Same as owner for: invite (center_admin & below), students/coaches/batches/enroll, attendance/performance, finance + **Refund**, leads/inventory/events, AI insights, all centers
- [ ] 🚫 Settings shows **no** "Academy settings" entry
- [ ] 🚫 Settings shows **no** "Subscription" entry
- [ ] 🚫 Invite dropdown does **not** offer `academy_admin` or `academy_owner` 🔒

## 3 · center_admin — `centeradmin@…`  (Center A only)
**Provisioning**
- [ ] ✅ Settings → Team → Invite: dropdown = head_coach/coach/trainer/parent/student
- [ ] ✅ Invite a head_coach → succeeds (lands in your center)
- [ ] 🚫 Dropdown does **not** offer center_admin / academy_admin / owner 🔒
**Scope (the isolation checks)**
- [ ] ✅ Settings → Sports: center picker locked to **Andheri**; enable a sport
- [ ] ✅ Students / Coaches / Batches: create + edit in Center A
- [ ] 🚫 Lists show **only Center A** — no Bandra students/coaches/batches/leads/inventory/events/invoices 🔒
- [ ] 🚫 No way to create a student/coach/batch in Center B (not offered; if forced → permission error) 🔒
- [ ] ✅ Finance: a Center A student → assign fee, record payment
- [ ] 🚫 **No Refund button** on payments 🔒
- [ ] 🚫 Settings shows no Academy settings / Subscription; can't add a Center (no FAB)
- [ ] ✅ AI insights on a Center A student

## 4 · head_coach — `headcoach@…`  (Center A, **cricket**)
**Provisioning**
- [ ] ✅ Top-bar invite icon **and** Home → Manage → Invite staff: dropdown = coach/trainer only
- [ ] 🚫 No option to invite center_admin/head_coach/parent/student 🔒
**Records (own center)**
- [ ] ✅ Home → Manage → Students → New: creates in Center A
- [ ] ✅ Home → Manage → Coaches → New: creates a coach record + sets sports
**Batches (own center + own sport)**
- [ ] ✅ Batches → New batch, sport = **Cricket** → saves
- [ ] 🚫 New batch with sport = **Football** → "permission denied" 🔒
- [ ] ✅ A batch with **no sport** in your center → saves (relaxation) 🔒
- [ ] ✅ Edit a cricket batch
- [ ] ✅ Enroll a student into a cricket batch
**Sessions**
- [ ] ✅ Batch → student → mark attendance / record performance (cricket batch)
- [ ] 🚫 Cannot act on a football/Bandra batch 🔒
- [ ] ✅ AI insights on a student
- [ ] 🚫 No finance/fees sections on the student page; no Refund

## 5 · coach — `coach@…`  (Center A)
- [ ] ✅ Top-bar/Manage invite: **trainer only** 🔒
- [ ] ✅ Home → Manage → Students → New: creates in Center A
- [ ] 🚫 No "Coaches" tile (can't create coach records) 🔒
- [ ] 🚫 No "New batch" FAB (can't create batches) 🔒
- [ ] ✅ Own batch → **enroll** a student
- [ ] 🚫 Cannot enroll into a batch you don't coach 🔒
- [ ] ✅ Own batch → mark attendance + **record performance**
- [ ] ✅ AI insights on a student in your batch
- [ ] 🚫 No finance sections; no Refund

## 6 · trainer — `trainer@…`  (Center B, staffs a batch)
- [ ] 🚫 **No invite icon** (provisions nobody) 🔒
- [ ] 🚫 No Manage → Students / Coaches (can't create) 🔒
- [ ] 🚫 No "New batch" FAB 🔒
- [ ] ✅ Own (staffed) batch → mark **attendance**
- [ ] ✅ Own batch → student → **record performance** (batch-scoped) 🔒
- [ ] 🚫 Cannot act on a batch you don't staff 🔒
- [ ] ✅ AI insights on an own-batch student
- [ ] ✅ Attach photo/video to an own-batch student
- [ ] 🚫 No finance

## 7 · parent — `parent@…`
- [ ] ✅ Dashboard → only **your child's** attendance / performance / invoices / dues
- [ ] ✅ AI insights for your child
- [ ] 🚫 No other students visible; no management actions 🔒

## 8 · student — `student@…`
- [ ] ✅ See your **own** sessions / attendance / performance
- [ ] ✅ AI insights for yourself
- [ ] 🚫 No other students; no management 🔒

## 9 · super_admin — `superadmin@…`  (web-admin console, not the app)
- [ ] ✅ Academies / plans / health / tickets across all academies
- [ ] (Not part of the mobile hierarchy; verified by the web-admin suite)

---

## Cross-cutting security — 🔒 all proven by pgTAP (spot-check optionally)
- [ ] 🔒 A self-signup with crafted metadata lands as `student`/no-academy (no escalation)
- [ ] 🔒 center_admin/head_coach cannot promote a coach to admin, nor move them to another center
- [ ] 🔒 No role sees another **academy's** data (cross-tenant)
- [ ] 🔒 Announcements: a non-admin sees only announcements delivered to them
- [ ] 🔒 Parent/student see only their own student's finance

## Known gaps (expected — NOT bugs; don't fail the run on these)
- ⚠️ **Assigning a trainer to a batch** (`batch_staff`) has RLS support but **no UI yet** — a trainer is reached only via `coach_id`. So a trainer can be tested only on the batch they're the coach of (the demo trainer is).
- ⚠️ A `batch_staff`-only trainer (not the batch's `coach_id`) can't navigate to that batch's students yet (their batch list is `coach_id`-based).
- ⚠️ NULL-`center_id` staff/students are manageable by every center_admin (soft-widening; fails safe).
- ⚠️ A center_admin's **dashboard KPI cards** may show academy-wide aggregates (materialized views bypass RLS); row-level lists ARE isolated.

---
**Pass criteria:** every ✅ works without error, every 🚫 is hidden or cleanly blocked, and the ⚠️ items behave as noted. Anything else → capture the screen + error and report it.
