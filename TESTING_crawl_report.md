# PlayHub mobile — exhaustive UI crawl report

Device: POCO M2 Pro (Android 12, 1080×2400) · driven via `adb` (uiautomator dumps + input).
Backend: live Supabase `hrawgduftgslwsdgzliy`. Demo logins, password `Demo@1234`.

## Method & safety policy
- **Code-grounded inventory** built first (workflow, 8 parallel readers): **113 screens / 735 controls**, each tagged `safe` / `unsafe` to perform on a live DB. Raw inventory: workflow output `wsznopufg.output`.
- **Performed for real (non-destructive):** navigation, opening every form/sheet/dropdown, filters/search, **create**, **edit/save**, enroll, mark attendance, record performance.
- **NOT performed (by request + safety):**
  - destructive — delete / archive / remove / withdraw / stop-billing (verified the control is *present + gated*, dialog not confirmed)
  - money — record payment / refund / Razorpay / subscription change
  - mass-outbound — invite-send (emails), announcement broadcast, chat send, "Resend verification" (drove the flow, did not hit final send)

## Coverage
Every role logged in and its shell + gating verified; the full owner surface + all create/edit paths crawled. ~45 of 113 screens exercised directly on-device; the remainder are create/edit variants of verified forms, money/destructive controls (intentionally skipped), or shared pages already covered under another role.

## Results by area — all PASS (loads + functions; no crashes/errors seen)

### Auth & shells
- LoginPage ✅ (8 logins), AccountSheet ✅, Profile entry ✅, OwnerHomeShell ✅, CoachHomeShell ✅, ParentHomeShell ✅, StudentHomeShell ✅, CenterAdminHomeTab ✅.

### Owner Home tab — every destination loads
- KPI dashboard ✅ · Custom report builder ✅ · Leads kanban ✅ (**created a lead "QALead"**) · Lead detail ✅ (Convert / Schedule actions) · Events ✅ (Draft/Published + New event) · Announcements ✅ (list of sent; compose not sent) · Notifications center ✅ · Messages ✅ (empty state) · Billing dashboard ✅ (Money/Setup/Reports tabs) · Inventory ✅ (items/vendors, reactive low-stock subtitle) · Today's sessions ✅ · Live attendance overview ✅.

### People & training (CRUD performed)
- Students: list/filters ✅, **create ✅ ("QATest Student")**, **edit ✅ (saved a City change)**.
- Coaches: list/filters ✅, **create ✅ ("QACoach Tester")**, **edit ✅ (saved a phone change)**.
- Batches: list ✅, **create ✅ (head_coach made "QACricketBatch", cricket)**, detail ✅ (Edit / Mark attendance / Enrol / More), enrol sheet ✅.
- Attendance marking ✅, Today's sessions ✅, Admin attendance overview ✅.
- Performance history + record-assessment entry ✅ (incl. trainer).
- Sports settings ✅, Academy settings ✅, Centers ✅, Support ✅, Activity log ✅ (shows the test creates/edits).

### Provisioning ladder (invite dropdowns) — all correct
owner → admin…student (no owner) · admin → center_admin…student (no admin/owner) · center_admin → head_coach…student · head_coach → coach/trainer · coach → trainer · trainer → none. Team-member "Remove" gated to the same ladder, hidden on self/owner.

### Role scope (spot highlights)
- center_admin: **11 students vs admin's 15** (center-A isolation) ✅; invite sheet omits the center picker.
- head_coach: batch sport-picker shows **only Cricket** ✅; MANAGE → Students/Coaches/Invite.
- coach: **Enrol present on own batch** ✅ (the earlier gap is fixed); no New-batch FAB, no Coaches tile, no Edit/Archive/finance.
- trainer: no invite/create/FAB; attendance + record-performance + AI/media on staffed batch; no finance.
- parent/student: read-only own data, no management.

## Findings / bugs
1. **academy_admin sees "Subscription" in Settings** — `capabilities.dart` gates `manageSubscription` to **owner-only**, and center_admin correctly doesn't see it, but `settings_tab.dart` renders the Subscription tile under `isOwnerOrAdmin`. Minor UI/capability-mirror inconsistency (RLS is still the real gate). Fix: move the tile to the `isOwner` branch.
   - *(No other defects observed — every screen crawled loaded and responded correctly.)*

## Not exercised (by policy) — present + gated, not fired
Delete/Archive/Remove/Withdraw/Stop-billing dialogs; Record payment / Refund / Razorpay / Subscription change; Invite-send, Announcement broadcast, Chat send, Resend-verification, document delete.

## Test data created on the live demo DB (for cleanup if desired)
- Student **QATest Student** (parent QAParent, city QACity)
- Coach **QACoach Tester** (phone 9998887776)
- Batch **QACricketBatch** (Cricket)
- Lead **QALead**
