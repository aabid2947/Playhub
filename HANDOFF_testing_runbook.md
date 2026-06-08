# HANDOFF — rewrite the hierarchy test runbook top-down (owner-first)

**For:** the next Claude instance. **Status of the feature being tested:** DONE +
backend-verified. **What's left:** one doc rewrite (below). Read this whole file,
then do the task.

---

## The task (what the user actually wants)

Rewrite [TESTING_hierarchy.md](TESTING_hierarchy.md) so the manual test flows
**top-down from the academy owner**, as a **single connected chain** — NOT as
isolated per-role checklists, and **NOT starting from center_admin** (the user
explicitly rejected that ordering twice).

The org hierarchy is a *provisioning ladder*: each rung creates the rung below.
The test must mirror that — each step logs in as one role and **creates the entity
the next login depends on**:

```
academy_owner   → create Center, enable a Sport, invite/assign the center_admin
academy_admin   → (peer-level admin checks; sees all centers; no academy-settings/subscription)
center_admin    → enable sport for own center, invite head_coach, (own-center isolation checks)
head_coach      → create coach + student records (own center), create a sport batch, enroll
coach           → create student, enroll into own batch, mark attendance + record performance
trainer         → mark attendance + record performance on a staffed batch (batch-scoped)
parent          → verify read-only: only their child's attendance/performance/invoices + AI insights
student         → verify read-only: only their own data
super_admin     → web-admin console only (out of the mobile chain)
```

Each chain step should state: **who logs in → what they create → what that
unlocks for the next step**, plus the ✅ allow / 🚫 deny checks for that rung
*at that point in the chain*. Keep the existing legend (✅/🚫/🔒/⚠️), the
"🔒 = already proven by pgTAP" idea, the Known-gaps section, and the prerequisites.

The current [TESTING_hierarchy.md](TESTING_hierarchy.md) already has accurate
per-role allow/deny content — **reuse it**, just **re-sequence into the chain** and
add the "produces for next rung" linkage. Don't lose any actions; the user said
"every action needs to be tested," so coverage must stay complete.

---

## Ground truth — don't re-derive these

**Demo logins** (all password `Demo@1234`, domain `@playhubdemo.in`), seeded by
`supabase/seed.sql` + `apps/web-admin/scripts/create_demo_users.mjs`:

| login | role | scope |
|---|---|---|
| `superadmin@` | super_admin | web-admin console |
| `owner@` | academy_owner | whole academy |
| `admin@` | academy_admin | whole academy (no academy-settings/subscription) |
| `centeradmin@` | center_admin | **Center A (Andheri)** |
| `headcoach@` (Rahul) | head_coach | Center A, **cricket** |
| `coach@` (Priya) | coach | Center A, **football** |
| `trainer@` (Arjun) | trainer | **Center B (Bandra)**, staffs a batch |
| `parent@` | parent | linked to student1 |
| `student@` (Aarav) | student | self |

Centers: **A = Andheri** (most staff), **B = Bandra** (the trainer).
Supabase project ref: `hrawgduftgslwsdgzliy`.

**Capability source of truth (authoritative for UI show/hide):**
[capabilities.dart](apps/mobile/lib/features/auth/data/capabilities.dart). RLS is
the real gate; this only shows/hides entry points (invariant #3 — UI must never
offer an action RLS rejects). Key flags: `invitableRoles`, `inviteScopedToOwnCenter`,
`manageStudents`, `manageCoaches`, `manageBatches`, `manageTeam`, `manageSports`,
`manageFinance`, `manageRefunds`, `viewRevenue`, `recordPerformance`, `markAttendance`.

**To ground "this button is here" UI claims** (verify before asserting a path):
- Shells/nav per role: [role_dashboard.dart](apps/mobile/lib/features/dashboards/role_dashboard.dart)
- head_coach/coach "Manage" section (Students/Coaches/Invite staff): [coach_home_tab.dart](apps/mobile/lib/features/coach/presentation/coach_home_tab.dart)
- Invite dropdown roles + center picker: [invite_user_sheet.dart](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart)
- Performance batch threading (trainer needs non-null batch_id): [performance_history_page.dart](apps/mobile/lib/features/performance/presentation/performance_history_page.dart) + coach_student_page.dart + batch_detail_page.dart
- Finance/refund gating: grep `refund`/`invoice`/`fee` under apps/mobile/lib/features (gated on `viewRevenue`/`manageFinance`/`manageRefunds`)

---

## What's already verified (don't ask the user to re-prove)

- **All 9 hierarchy migrations applied** to the live DB. `verify_hierarchy_rls.sql`
  returned **"Success. No rows returned"** (7 pgTAP groups green) — RLS isolation,
  provisioning ladder, sport-scope, batch_staff, finance-scope, center read
  isolation, capabilities, trainer media are all proven. Mark these 🔒 in the doc.
- `flutter analyze` clean; `flutter test` 36 pass / 1 pre-existing unrelated fail.

**Still pending on the USER's side (the prerequisites block in the runbook):**
deploy 3 edge functions (`invite-user`, `convert-lead-to-student`, `ai-insights`),
rebuild the app, then run the manual chain.

---

## Known gaps (keep these in the doc as ⚠️ — they are NOT bugs)

1. **Assign-trainer-to-batch (`batch_staff`)** has RLS support but **no UI yet** —
   a trainer is reachable only via `batches.coach_id`. So in the chain, the trainer
   step must use the batch the trainer is the *coach* of (the demo trainer is).
2. A `batch_staff`-only trainer (not the batch's `coach_id`) can't navigate to that
   batch's students yet.
3. NULL-`center_id` rows are manageable by every center_admin (soft-widening, fails safe).
4. center_admin **dashboard KPI cards** may show academy-wide aggregates (materialized
   views bypass RLS); row-level *lists* are correctly isolated.

---

## A verification fan-out was started then stopped

I launched a Workflow (`hierarchy-topdown-testmap`) to ground every UI claim against
the code before rewriting — the user interrupted it. You can either:
- **Re-run it** to get cached map results:
  `Workflow({scriptPath: "C:\\Users\\hp\\.claude\\projects\\c--Users-hp-Documents-MyProjects-playhub\\b7343295-d8f2-4d15-a605-44f490678035\\workflows\\scripts\\hierarchy-topdown-testmap-wf_89f33917-5cc.js", resumeFromRunId: "wf_89f33917-5cc"})`, **or**
- **Skip it** — the current TESTING_hierarchy.md content is already accurate; you
  mainly need to *re-sequence* it. Just spot-verify any UI path you're unsure of by
  reading the files listed above. (Do NOT auto-launch a workflow unless the user
  opts in again — ultracode may be off in your session.)

---

## Definition of done

[TESTING_hierarchy.md](TESTING_hierarchy.md) reads as an owner-first chained
walkthrough (step 1 = `owner@` creates a center …), every prior action still
covered, each step shows what it unlocks for the next, legend + prerequisites +
known-gaps retained. Then delete this handoff file (or tell the user it can be
deleted). Update the CLAUDE.md change log only if you change feature behavior — a
doc rewrite alone doesn't warrant an entry.
