# REVAMP_PROGRESS.md — screen tracker, role map & component map

> **Companion to [REVAMP.md](REVAMP.md).** REVAMP.md is the *how* (per-screen brief
> + shared anatomies). **This file is the *what's-left*, the *who-sees-it*, and the
> *where-is-it*** — every screen, its effort tier, the **roles** that reach it, its
> status, and all its nested components so you don't have to grep.
>
> **Recommended workflow — revamp one role's surface at a time.** Pick a role from
> the [Revamp by role](#revamp-by-role) index, revamp every screen in its set, then
> log in as that role and review the whole surface coherently. Move to the next role.
>
> **Marking done:** flip `[ ]`→`[x]`, `🟡 Pending`→`🟢 Done`, fill the `done:` slot,
> and update the **Progress** counts.

---

## Legend

**Effort tier** — 🟢 Easy (one page, quick) · 🟡 Medium (list+filters / multi-section
form / detail w/ several parts) · 🔴 Hard (4+ nested parts, embedded sections,
charts, or sets a reused pattern).

**Status** — `🟡 Pending` / `🟢 Done`.

**Roles** (👤) — which user types can navigate to the screen. Codes:

| Code | Role | Shell |
|---|---|---|
| `SA` | super_admin | SuperAdminHomeShell |
| `OW` | academy_owner | OwnerHomeShell (HomeTab) |
| `AD` | academy_admin | OwnerHomeShell (HomeTab) |
| `CA` | center_admin | OwnerHomeShell (**CenterAdminHomeTab**) — center-scoped, finance view-only |
| `HC` | head_coach | CoachHomeShell |
| `CO` | coach | CoachHomeShell |
| `TR` | trainer | CoachHomeShell |
| `PA` | parent | ParentHomeShell |
| `ST` | student | StudentHomeShell (= parent surface, RLS-narrowed) |
| `ALL` | every authenticated role | — |
| `Unauth` | signed-out (auth flow) | — |

> Roles come from [capabilities.dart](apps/mobile/lib/features/auth/data/capabilities.dart)
> + the shell/home/settings gating. RLS still narrows *data* (e.g. `CA` sees only
> their center); the tag is about who reaches the *screen*. "view-only" roles see the
> screen but its mutating actions are gated off.

**Nested** — private `_Widgets` in the same file + embedded shared sections (linked)
+ shared widgets rendered. "Hosts:" = a shell/tab that mounts other pages.

---

## Progress

**Tier marks below stay 🟡 until the analyze gate + visual review** (see status note).
Tier: 🟢 Easy 0/29 · 🟡 Medium 0/38 · 🔴 Hard 0/17 marked Done.
**Shared units 0 / 5 marked Done.**

> **2026-06-06 — center_admin full-surface workflow COMPLETE.** 46 screens revamped
> + adversarially verified (tally: 39 clean · 7 auto-fixed · **0 issues**), via
> `center-admin-revamp` workflow (run wf_e89571d3-2bd, 93 agents). Edits are in the
> working tree. **Not yet marked Done** because two gates remain: (1) a single
> `flutter analyze` in apps/mobile (49 files changed by parallel agents), (2) visual
> review logged in as center_admin. Open follow-ups from the consistency pass:
> 3 ungated/inline-gated create FABs (leads, inventory, events → should use caps.*),
> + ~7 polish items (filter affordance, filtered-empty state, tile rhythm,
> result-count text role, lead_detail error branch, batch_detail redundant badge,
> refresh affordance). Flip these rows to 🟢 Done after analyze + review.

By role surface (each role's *complete* set; screens overlap between roles):
- 👤 `CA` center_admin — **46 revamped + verified (0 issues)** ← *pending analyze + visual review*
- 👤 `OW`/`AD` owner+admin — 0 / ~55
- 👤 `HC` head_coach — **9 revamped + verified** (coach shell + home/batches/student tabs + threads/notifications + kpi + event_results) ← *double-AppBar shell regression fixed + analyze-clean; pending visual review. `CO`/`TR` reuse these.*

> **2026-06-06 — head_coach surface workflow + fix.** 9 screens revamped/verified (run wf_2915b140-69e, 19 agents, 9 clean / 0 issues). The consistency pass caught a DOUBLE-APPBAR regression in `coach_home_shell` (the canonical owner-shell contract gave the coach shell its own AppBar while its full-page tabs keep theirs). **Fixed manually:** reverted the coach shell to no top-level AppBar (coach tabs are full pages, unlike owner's app-bar-less body tabs) and moved the single account entry point onto the Home tab's AppBar. `flutter analyze` of the two files = 0 errors (5 pre-existing fl_chart info-lints remain for the broader sweep). Open follow-up: `parent_home_shell`/`student_home_shell` still lack the account entry point — do in the parent batch; the fully-persistent-shell-bar option (an `embedded` flag on the shared threads/notifications/announcements pages) is deferred so coach + parent can move together.
- 👤 `PA`/`ST` parent+student — **done** (parent_dashboard_tab revamped + verified, analyze-clean; the shells need no change — account entry lives on the dashboard tab's AppBar, coach archetype)

> **2026-06-06 — parent/student surface + header fix.** Revamped `parent_dashboard_tab` (also the student dashboard via shell inheritance): persistent student switcher, priority "This week" group (next session + dues) first, grouped sections, a confirm step before Razorpay pay, AppBar = BrandWordmark + AccountAction. `parent_home_shell`/`student_home_shell` unchanged (appbar-less, full-page tabs). **Also fixed user-reported header regression in `owner_home_shell`:** its AppBar title changed per tab ("Students/Coaches/Batches/Settings"), duplicating the bottom-nav label — now shows the **brand wordmark on every tab** (bottom nav indicates the active tab). `flutter analyze` of all three files = 0 errors. **Design principle confirmed:** the top header is the brand wordmark, never a per-tab title; the bottom nav labels the tab.
- 👤 `SA` super_admin — **done** (shell + health/academies/plans/tickets revamped + verified, 0 issues; cohesive)

> **2026-06-06 — super_admin surface workflow.** 5 screens revamped/verified (run wf_8227bbda-0f0, 11 agents, 4 clean / 1 fixed / 0 issues, cohesive:true). Shell = owner archetype done right: ONE constant AppBar (BrandWordmark + `AppBadge('Admin')` + `AccountAction`), appbar-less tab bodies — both prior header bugs avoided. Verify removed `plans_page`'s latent double-bar (nested Scaffold-for-FAB) + a duplicated "Unlimited" label. Wins: confirm before academy `is_active` toggle + before plan delete; `AppBadge` for subscription/priority status. **Minor cohesion polish open (not bugs):** unify list bottom-padding across academies/plans/tickets; add a result-count line to plans + tickets; give super_tickets a top in-body header; pagination cue deferred on the 3 lists. **Cross-surface note for the admin batch:** `support_page` (owner/admin, un-revamped) should be brought up to the now-finished super-tickets `_TicketDetailPage` thread pattern (AppBadge status/priority, author+timestamp reply bubbles).

> **2026-06-06 — persistent PlayHub bar on coach + parent/student shells.** Per user request, `coach_home_shell` and `parent_home_shell` (→ `student_home_shell` via inheritance) now use the **owner archetype**: ONE persistent top AppBar = `BrandWordmark` + `AccountAction`, with the bottom nav labelling the tab (header never repeats it). All five shells (owner · super_admin · coach · parent · student) are now consistent. **Convention introduced — the `embedded` flag:** shared full-page tabs (`threads_page`, `notification_center_page`, `announcements_page`) take `embedded: bool = false`; a shell that owns the AppBar passes `embedded: true` to suppress the page's own bar (no double bar), while pushed/standalone routes keep the default (bar + back button). `notification_center` surfaces its mark-all-read + preferences in an in-body toolbar when embedded (coach/parent have no Settings tab). Home tabs (`coach_home_tab`, `parent_dashboard_tab`) + `coach_batches_tab` are now app-bar-less bodies. Whole-app `flutter analyze` = 0 errors. **When adding a tab to any shell, suppress its AppBar via this pattern, never stack a second bar.**

> Update these whenever you mark a screen done.

---

## Revamp by role

The actionable batches. A screen appears under **every** role that reaches it, so the
same file may be in two batches — revamp it once, it counts for all. Do a role
top-to-bottom, then log in as that role to review.

### 👤 `CA` — center_admin *(active — Wave plan below)*
**Frame (Wave 1 — first thing you see on login):** owner_home_shell · center_admin_home_tab · settings_tab · profile_page · students_tab · coaches_tab · batches_tab
**Home destinations + Settings (Wave 2):** todays_sessions_page · admin_attendance_overview · leads_kanban_page · events_page · inventory_page · centers_tab · centers_page · center_form_page · sports_settings_page · audit_log_page
**Detail / form / section screens (Wave 3):** student_form_page · student_documents_section · student_bulk_import_page · coach_form_page · coach_documents_section · coach_bulk_import_page · batch_form_page · batch_detail_page · schedule_picker · attendance_marking_page · performance_history_page · performance_form_page · performance_detail_page · lead_detail_page · lead_form_page · lead_convert_sheet · event_detail_page · event_form_page · event_register_sheet · inventory_item_page · inventory_item_form_page · vendors_page · movement_sheet · sport_picker · thread_detail_page · batch_chat_button · message_parent_button · student_fees_section* · student_discounts_section* · batch_fees_section* · batch_discounts_section* · announcements_page (feed only)
> *finance sections are **view-only** for `CA` — keep the `manageFinance` gate that hides the assign/deactivate actions.

### 👤 `OW`/`AD` — owner + admin
Everything in `CA`'s set **plus**: home_tab · academy_settings_page · team_page · invite_user_sheet · subscription_page · the full **billing** set (billing_dashboard_page · invoice_list_page · invoice_detail_page · record_payment_page · payments_list_page · refund_form_page · fee_structures_page · fee_structure_form_page · discount_structures_page · discount_structure_form_page · financial_reports_page) · announcement_composer_page · kpi_dashboard_page · report_builder_page · support_page · threads_page · notification_center_page · notification_preferences_page. (`OW` also: setup_academy_page.)

### 👤 `HC`/`CO`/`TR` — head_coach / coach / trainer
coach_home_shell · coach_home_tab · coach_batches_tab · coach_student_page · batch_detail_page · todays_sessions_page · attendance_marking_page · performance_history_page · performance_form_page · performance_detail_page · batch_chat_button · message_parent_button · thread_detail_page · threads_page · announcements_page · notification_center_page · notification_preferences_page · events_page · event_detail_page · event_results_page · profile_page. (`HC` also: event_form_page · kpi_dashboard_page.) (`CO`/`HC` record performance; `TR` does not.)

### 👤 `PA`/`ST` — parent / student
parent_home_shell (`PA`) / student_home_shell (`ST`) · parent_dashboard_tab · announcements_page · threads_page · thread_detail_page · notification_center_page · notification_preferences_page · events_page · event_detail_page · event_register_sheet · profile_page.

### 👤 `SA` — super_admin
super_admin_home_shell · global_health_page · academies_page · plans_page · super_tickets_page · profile_page.

---

## Shared units — do these first within any role batch (revamp once, reused)

- [ ] **`shared docs section`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [student_documents_section.dart](apps/mobile/lib/features/students/presentation/student_documents_section.dart) + [coach_documents_section.dart](apps/mobile/lib/features/coaches/presentation/coach_documents_section.dart). Nested: `_DocumentTile`, type-picker sheet.
- [ ] **`shared fee-assignment section`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA(view) — *done: —*
  - [batch_fees_section.dart](apps/mobile/lib/features/billing/presentation/batch_fees_section.dart) + [student_fees_section.dart](apps/mobile/lib/features/billing/presentation/student_fees_section.dart). Nested: `_AssignmentTile`, `_AssignSheet`. Gate assign/deactivate on `manageFinance`.
- [ ] **`shared discount-assignment section`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA(view) — *done: —*
  - [batch_discounts_section.dart](apps/mobile/lib/features/billing/presentation/batch_discounts_section.dart) + [student_discounts_section.dart](apps/mobile/lib/features/billing/presentation/student_discounts_section.dart). Nested: `_Tile`, `_Sheet`.
- [ ] **`sport_picker.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA HC — *done: —*
  - [sport_picker.dart](apps/mobile/lib/features/sports/presentation/sport_picker.dart). `SportPicker`, `SportFilterChipBar`, `SportMultiSelect`. Normalize empty states.
- [ ] **`schedule_picker.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA HC — *done: —*
  - [schedule_picker.dart](apps/mobile/lib/features/batches/presentation/schedule_picker.dart). Nested: `_TimeField`.

---

## §4.1 — App shells & navigation *(do first; sets the frame)*

- [ ] **`owner_home_shell.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [owner_home_shell.dart](apps/mobile/lib/features/home/owner_home_shell.dart). **Defines the canonical shell contract** (AppBar rule + single account entry point). Hosts: HomeTab/CenterAdminHomeTab, StudentsTab, CoachesTab, BatchesTab, SettingsTab. Renders: `BrandWordmark`, `VerificationBanner`.
- [ ] **`coach_home_shell.dart`** — 🟢 Easy — 🟡 Pending — 👤 HC CO TR — *done: —*
  - [coach_home_shell.dart](apps/mobile/lib/features/coach/presentation/coach_home_shell.dart). Hosts: CoachHomeTab, CoachBatchesTab, AnnouncementsPage, ThreadsPage, NotificationCenterPage. Renders: `CountBadgeIcon`.
- [ ] **`parent_home_shell.dart`** — 🟢 Easy — 🟡 Pending — 👤 PA — *done: —*
  - [parent_home_shell.dart](apps/mobile/lib/features/parent/presentation/parent_home_shell.dart). Hosts: ParentDashboardTab, AnnouncementsPage, ThreadsPage, NotificationCenterPage. Renders: `CountBadgeIcon`.
- [ ] **`student_home_shell.dart`** — 🟢 Easy — 🟡 Pending — 👤 ST — *done: —*
  - [student_home_shell.dart](apps/mobile/lib/features/student/presentation/student_home_shell.dart). Subclass of ParentHomeShell — keep the inheritance.
- [ ] **`super_admin_home_shell.dart`** — 🟢 Easy — 🟡 Pending — 👤 SA — *done: —*
  - [super_admin_home_shell.dart](apps/mobile/lib/features/super_admin/presentation/super_admin_home_shell.dart). Hosts: GlobalHealthPage, AcademiesPage, PlansPage, SuperTicketsPage. Replace hand-rolled "Admin" badge with `AppBadge`.
- [ ] **`settings_tab.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [settings_tab.dart](apps/mobile/lib/features/settings/settings_tab.dart). Flat role-gated list → group under `AppSectionHeader`s. Keep every role gate (academy-settings=OW only; team/subscription/support=OW+AD; centers/sports/activity=all three).
- [ ] **`role_dashboard.dart`** — 🟢 Easy — 🟡 Pending — 👤 ALL — *done: —*
  - [role_dashboard.dart](apps/mobile/lib/features/dashboards/role_dashboard.dart). **States only** (loading/stub/error) — do NOT touch routing logic. Nested: `_RoleStub`.
- [ ] **`auth_scaffold.dart`** — 🟡 Medium — 🟡 Pending — 👤 Unauth — *done: —*
  - [auth_scaffold.dart](apps/mobile/lib/features/auth/presentation/auth_scaffold.dart). Shared frame for §4.3. Nested: `BrandMark`, `AuthMessage`, `BrandWordmark`.

---

## §4.2 — Home dashboards / landing tabs *(do early)*

- [ ] **`home_tab.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD — *done: —*
  - [home_tab.dart](apps/mobile/lib/features/home/home_tab.dart). 11-item flat menu → grouped KPI dashboard (§3.4 reference fix). Nested: greeting card, academy card, `_ActionsCard`, two stat rows.
- [ ] **`center_admin_home_tab.dart`** — 🟡 Medium — 🟡 Pending — 👤 CA — *done: —*
  - [center_admin_home_tab.dart](apps/mobile/lib/features/home/center_admin_home_tab.dart). Nested: greeting card, stat row, `_ActionCard` (5 tiles: today's sessions, live attendance, leads, events, inventory).
- [ ] **`coach_home_tab.dart`** — 🟡 Medium — 🟡 Pending — 👤 HC CO TR — *done: —*
  - [coach_home_tab.dart](apps/mobile/lib/features/coach/presentation/coach_home_tab.dart). Nested: `_StatsRow`, `_AttendanceTrendCard` (fl_chart bar), `_BatchRow`.
- [ ] **`parent_dashboard_tab.dart`** — 🔴 Hard — 🟡 Pending — 👤 PA ST — *done: —*
  - [parent_dashboard_tab.dart](apps/mobile/lib/features/parent/presentation/parent_dashboard_tab.dart). **Also the student dashboard** (shared via inheritance). Nested: `SegmentedButton` switcher, `_StudentHeader`, `_UpcomingSessionsCard`, `_BatchesCard`, `_AttendanceCard`, `_PerformanceCard`, `_MediaGalleryCard`, `_OutstandingCard` (RazorpayCheckout).

---

## §4.3 — Auth & onboarding

- [ ] **`splash_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 Unauth — *done: —*
  - [splash_page.dart](apps/mobile/lib/features/auth/presentation/splash_page.dart). Renders: `BrandMark`.
- [ ] **`login_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 Unauth — *done: —*
  - [login_page.dart](apps/mobile/lib/features/auth/presentation/login_page.dart). Wraps `AuthScaffold`.
- [ ] **`signup_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 Unauth — *done: —*
  - [signup_page.dart](apps/mobile/lib/features/auth/presentation/signup_page.dart). Wraps `AuthScaffold`.
- [ ] **`forgot_password_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 Unauth — *done: —*
  - [forgot_password_page.dart](apps/mobile/lib/features/auth/presentation/forgot_password_page.dart). Wraps `AuthScaffold`.
- [ ] **`set_new_password_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 Unauth — *done: —*
  - [set_new_password_page.dart](apps/mobile/lib/features/auth/presentation/set_new_password_page.dart). Independent obscure toggles.
- [ ] **`profile_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 ALL — *done: —*
  - [profile_page.dart](apps/mobile/lib/features/auth/presentation/profile_page.dart). Nested: `_AvatarPreview`. Split editable vs read-only.
- [ ] **`setup_academy_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW — *done: —*
  - [setup_academy_page.dart](apps/mobile/lib/features/dashboards/setup_academy_page.dart). Align error styling with `AuthMessage`.

---

## §4.4 — People & org management

- [ ] **`students_tab.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [students_tab.dart](apps/mobile/lib/features/students/presentation/students_tab.dart). **Template for coach/team lists.** Nested: student tiles, filter sheet. Renders: `SportFilterChipBar`, `AppListTile`, `AppBadge`.
- [ ] **`student_form_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [student_form_page.dart](apps/mobile/lib/features/students/presentation/student_form_page.dart). Embeds StudentFeesSection, StudentDiscountsSection, StudentDocumentsSection. Renders: `AvatarPicker`, `SportPicker`, parent/student-login tiles, `InviteUserSheet`.
- [ ] **`coaches_tab.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [coaches_tab.dart](apps/mobile/lib/features/coaches/presentation/coaches_tab.dart). Match the students_tab template. Nested: `_CoachTile`.
- [ ] **`coach_form_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [coach_form_page.dart](apps/mobile/lib/features/coaches/presentation/coach_form_page.dart). Embeds CoachDocumentsSection. Renders: `AvatarPicker`, `SportMultiSelect`, login/invite card, `InviteUserSheet`.
- [ ] **`student_bulk_import_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [student_bulk_import_page.dart](apps/mobile/lib/features/students/presentation/student_bulk_import_page.dart). Nested: preview `DataTable`, result card.
- [ ] **`coach_bulk_import_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [coach_bulk_import_page.dart](apps/mobile/lib/features/coaches/presentation/coach_bulk_import_page.dart).
- [ ] **`centers_tab.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [centers_tab.dart](apps/mobile/lib/features/centers/presentation/centers_tab.dart). Nested: center tiles, `_EmptyState`. Kill duplicate empty-CTA+FAB; status `AppBadge`.
- [ ] **`centers_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [centers_page.dart](apps/mobile/lib/features/centers/presentation/centers_page.dart). AppBar wrapper around CentersTab — resolve double-header.
- [ ] **`center_form_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [center_form_page.dart](apps/mobile/lib/features/centers/presentation/center_form_page.dart). Expose model fields; separate activate/deactivate.
- [ ] **`team_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [team_page.dart](apps/mobile/lib/features/users/presentation/team_page.dart). Group members by role. Renders: [InviteUserSheet](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart).
- [ ] **`invite_user_sheet.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD — *done: —*
  - [invite_user_sheet.dart](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart). Shared sheet. Uses `InvitePreset`.
- [ ] **`academy_settings_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW — *done: —*
  - [academy_settings_page.dart](apps/mobile/lib/features/academy/presentation/academy_settings_page.dart). 4 sections (Profile/Hours/Holidays/Invoicing). Nested: `AvatarPicker`, hours pickers, holiday chips.
- [ ] **`sports_settings_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [sports_settings_page.dart](apps/mobile/lib/features/sports/presentation/sports_settings_page.dart). Nested: `_CenterSportsList`, `_SportRow`, `_AddSportSheet`.

---

## §4.5 — Training operations

- [ ] **`batches_tab.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [batches_tab.dart](apps/mobile/lib/features/batches/presentation/batches_tab.dart). Renders: `SportFilterChipBar`, batch tiles, capacity `AppBadge`.
- [ ] **`batch_form_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [batch_form_page.dart](apps/mobile/lib/features/batches/presentation/batch_form_page.dart). Embeds SchedulePicker. Renders: `SportPicker`, center/coach dropdowns.
- [ ] **`batch_detail_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA HC CO TR — *done: —*
  - [batch_detail_page.dart](apps/mobile/lib/features/batches/presentation/batch_detail_page.dart). 3 repeated enrollment sections → one. Nested: metadata card, `_EnrollmentSection`, enroll/transfer sheets. Embeds BatchFeesSection, BatchDiscountsSection (view-only for CA + hidden for coaches via viewRevenue). Renders: `BatchChatButton`, `MessageParentButton`.
- [ ] **`todays_sessions_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA HC CO TR — *done: —*
  - [todays_sessions_page.dart](apps/mobile/lib/features/attendance/presentation/todays_sessions_page.dart). Nested: `_SessionTile`.
- [ ] **`attendance_marking_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA HC CO TR — *done: —*
  - [attendance_marking_page.dart](apps/mobile/lib/features/attendance/presentation/attendance_marking_page.dart). Nested: `_DateHeader`, `_StudentRow`. Reserved note area; human date; completion cue.
- [ ] **`admin_attendance_overview.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [admin_attendance_overview.dart](apps/mobile/lib/features/attendance/presentation/admin_attendance_overview.dart). Realtime stream. Nested: `_SummaryRow`, `_Cell`, `_StatusDot`.
- [ ] **`performance_form_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA HC CO — *done: —*
  - [performance_form_page.dart](apps/mobile/lib/features/performance/presentation/performance_form_page.dart). Nested: `_SkillRow`, evidence section. Renders: `SportPicker`.
- [ ] **`performance_detail_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA HC CO — *done: —*
  - [performance_detail_page.dart](apps/mobile/lib/features/performance/presentation/performance_detail_page.dart). Score callout + skills + feedback + media.
- [ ] **`performance_history_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA HC CO — *done: —*
  - [performance_history_page.dart](apps/mobile/lib/features/performance/presentation/performance_history_page.dart). Nested: `_TrendCard`, `_AssessmentTile`. Single create path.
- [ ] **`coach_batches_tab.dart`** — 🟢 Easy — 🟡 Pending — 👤 HC CO TR — *done: —*
  - [coach_batches_tab.dart](apps/mobile/lib/features/coach/presentation/coach_batches_tab.dart). Renders: `BatchChatButton`.
- [ ] **`coach_student_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 HC CO TR — *done: —*
  - [coach_student_page.dart](apps/mobile/lib/features/coach/presentation/coach_student_page.dart). Nested: `_StudentMediaCard`, `_MediaThumb`. Renders: `MessageParentButton`.

---

## §4.6 — Billing & subscription

- [ ] **`billing_dashboard_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [billing_dashboard_page.dart](apps/mobile/lib/features/billing/presentation/billing_dashboard_page.dart). Hosts (TabBar): InvoiceListPage, FeeStructuresPage, DiscountStructuresPage, PaymentsListPage, FinancialReportsPage.
- [ ] **`invoice_list_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [invoice_list_page.dart](apps/mobile/lib/features/billing/presentation/invoice_list_page.dart). Unified filter + count + overdue `AppBadge`.
- [ ] **`invoice_detail_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD — *done: —*
  - [invoice_detail_page.dart](apps/mobile/lib/features/billing/presentation/invoice_detail_page.dart). Nested: `_SummaryCard`, `_OutstandingActions`, `_PaymentTile`, line items. `AppSectionHeader` not plain `Text`.
- [ ] **`record_payment_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD — *done: —*
  - [record_payment_page.dart](apps/mobile/lib/features/billing/presentation/record_payment_page.dart). Confirm + INR cue.
- [ ] **`payments_list_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [payments_list_page.dart](apps/mobile/lib/features/billing/presentation/payments_list_page.dart). Date-grouped; tappable→invoice; load-more.
- [ ] **`refund_form_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD — *done: —*
  - [refund_form_page.dart](apps/mobile/lib/features/billing/presentation/refund_form_page.dart). Nested: `_RefundNote`.
- [ ] **`fee_structures_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [fee_structures_page.dart](apps/mobile/lib/features/billing/presentation/fee_structures_page.dart). Nested: `_FeeTile`.
- [ ] **`fee_structure_form_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [fee_structure_form_page.dart](apps/mobile/lib/features/billing/presentation/fee_structure_form_page.dart). Grouped (Fee/Late fee/Status).
- [ ] **`discount_structures_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD — *done: —*
  - [discount_structures_page.dart](apps/mobile/lib/features/billing/presentation/discount_structures_page.dart). Nested: `_DiscountTile`.
- [ ] **`discount_structure_form_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD — *done: —*
  - [discount_structure_form_page.dart](apps/mobile/lib/features/billing/presentation/discount_structure_form_page.dart).
- [ ] **`financial_reports_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [financial_reports_page.dart](apps/mobile/lib/features/billing/presentation/financial_reports_page.dart). Nested: `_BigStat`. By-status rows tap → filtered invoices.
- [ ] **`subscription_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [subscription_page.dart](apps/mobile/lib/features/subscription/presentation/subscription_page.dart). Nested: `_CurrentPlanCard`, `_PlanCard`.

---

## §4.7 — Engagement

- [ ] **`leads_kanban_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [leads_kanban_page.dart](apps/mobile/lib/features/leads/presentation/leads_kanban_page.dart). Nested: `_Column`, `_Header`, `_Card`.
- [ ] **`lead_detail_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [lead_detail_page.dart](apps/mobile/lib/features/leads/presentation/lead_detail_page.dart). Nested: `_Header`, `_StatusActions`, `_Contact`, `_AddNoteRow`, `_ActivityTile`. Renders: [LeadConvertSheet](apps/mobile/lib/features/leads/presentation/lead_convert_sheet.dart).
- [ ] **`lead_form_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [lead_form_page.dart](apps/mobile/lib/features/leads/presentation/lead_form_page.dart). Renders: `SportPicker`.
- [ ] **`lead_convert_sheet.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [lead_convert_sheet.dart](apps/mobile/lib/features/leads/presentation/lead_convert_sheet.dart).
- [ ] **`announcements_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 ALL — *done: —*
  - [announcements_page.dart](apps/mobile/lib/features/announcements/presentation/announcements_page.dart). Nested: `_AdminList` (OW/AD), `_Feed` (everyone). Unify the two views.
- [ ] **`announcement_composer_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [announcement_composer_page.dart](apps/mobile/lib/features/announcements/presentation/announcement_composer_page.dart). Nested: `_RoleChips`, `_BatchPicker`, `_CenterPicker`.
- [ ] **`threads_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD HC CO TR PA ST — *done: —*
  - [threads_page.dart](apps/mobile/lib/features/chat/presentation/threads_page.dart). Nested: `_Tile`.
- [ ] **`thread_detail_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA HC CO TR PA ST — *done: —*
  - [thread_detail_page.dart](apps/mobile/lib/features/chat/presentation/thread_detail_page.dart). Realtime chat. Nested: `_MessageBubble`, attachment sheet, pending tray, composer.
- [ ] **`batch_chat_button.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA HC CO TR — *done: —*
  - [batch_chat_button.dart](apps/mobile/lib/features/chat/presentation/batch_chat_button.dart). Shared button.
- [ ] **`message_parent_button.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA HC CO TR — *done: —*
  - [message_parent_button.dart](apps/mobile/lib/features/chat/presentation/message_parent_button.dart). Uses `_LinkedParent`, picker sheet.
- [ ] **`notification_center_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD HC CO TR PA ST — *done: —*
  - [notification_center_page.dart](apps/mobile/lib/features/notifications/presentation/notification_center_page.dart). Nested: `_Tile`. Group by date.
- [ ] **`notification_preferences_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD HC CO TR PA ST — *done: —*
  - [notification_preferences_page.dart](apps/mobile/lib/features/notifications/presentation/notification_preferences_page.dart). 24 toggles → category × channel matrix.
- [ ] **`events_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA HC PA ST — *done: —*
  - [events_page.dart](apps/mobile/lib/features/events/presentation/events_page.dart). Nested: `_FilterBar`, `_StatusChip`. Renders: `SportFilterChipBar`.
- [ ] **`event_detail_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD CA HC PA ST — *done: —*
  - [event_detail_page.dart](apps/mobile/lib/features/events/presentation/event_detail_page.dart). Nested: `_Header`, `_ManageBar`, `_RegistrationsSection`, `_RegRow`. Renders: [EventRegisterSheet](apps/mobile/lib/features/events/presentation/event_register_sheet.dart).
- [ ] **`event_form_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA HC — *done: —*
  - [event_form_page.dart](apps/mobile/lib/features/events/presentation/event_form_page.dart). Nested: `_dateRow`. Renders: `SportPicker`.
- [ ] **`event_register_sheet.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA HC PA ST — *done: —*
  - [event_register_sheet.dart](apps/mobile/lib/features/events/presentation/event_register_sheet.dart).
- [ ] **`event_results_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD HC CO — *done: —*
  - [event_results_page.dart](apps/mobile/lib/features/events/presentation/event_results_page.dart). Nested: `_ResultRow`.

---

## §4.8 — Growth, analytics & inventory

- [ ] **`inventory_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [inventory_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_page.dart). Hosts (TabBar): All / Low stock / Vendors. Nested: `_ItemsList`.
- [ ] **`inventory_item_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [inventory_item_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_item_page.dart). Nested: `_StockCard`, `_InlineNote`, movement tiles. Renders: [MovementSheet](apps/mobile/lib/features/inventory/presentation/movement_sheet.dart).
- [ ] **`inventory_item_form_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [inventory_item_form_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_item_form_page.dart).
- [ ] **`vendors_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [vendors_page.dart](apps/mobile/lib/features/inventory/presentation/vendors_page.dart). Nested: `_VendorSheet`.
- [ ] **`movement_sheet.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [movement_sheet.dart](apps/mobile/lib/features/inventory/presentation/movement_sheet.dart). Reserve space for conditional dropdowns.
- [ ] **`kpi_dashboard_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD HC — *done: —*
  - [kpi_dashboard_page.dart](apps/mobile/lib/features/analytics/presentation/kpi_dashboard_page.dart). Nested: `CollectionSummaryCard`, `RevenueTrendCard`, `EnrollmentTrendCard`, `SportBreakdownCard`, `BatchUtilizationCard`, `LeadFunnelCard`.
- [ ] **`report_builder_page.dart`** — 🔴 Hard — 🟡 Pending — 👤 OW AD — *done: —*
  - [report_builder_page.dart](apps/mobile/lib/features/reports/presentation/report_builder_page.dart). Nested: `_FilterEditor`, `_FilterRow`, `_ResultTable`.
- [ ] **`audit_log_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD CA — *done: —*
  - [audit_log_page.dart](apps/mobile/lib/features/audit/presentation/audit_log_page.dart). Nested: `ExpansionTile` rows, `_DiffRow`, `_Json`.
- [ ] **`support_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 OW AD — *done: —*
  - [support_page.dart](apps/mobile/lib/features/support/presentation/support_page.dart). Nested: `_NewTicketSheet`, `_TicketThreadPage`.

---

## §4.9 — Super-admin (platform)

- [ ] **`global_health_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 SA — *done: —*
  - [global_health_page.dart](apps/mobile/lib/features/super_admin/presentation/global_health_page.dart). Nested: `GlobalRevenueCard`, status `AppStatTile` grid.
- [ ] **`academies_page.dart`** — 🟢 Easy — 🟡 Pending — 👤 SA — *done: —*
  - [academies_page.dart](apps/mobile/lib/features/super_admin/presentation/academies_page.dart). Confirm before toggling is_active.
- [ ] **`plans_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 SA — *done: —*
  - [plans_page.dart](apps/mobile/lib/features/super_admin/presentation/plans_page.dart). Nested: `_PlanSheet`.
- [ ] **`super_tickets_page.dart`** — 🟡 Medium — 🟡 Pending — 👤 SA — *done: —*
  - [super_tickets_page.dart](apps/mobile/lib/features/super_admin/presentation/super_tickets_page.dart). Nested: `_TicketDetailPage`.

---

## Notes

- **A "screen" = the page + all its nested components.** The `Nested:` line is your
  checklist of what to touch.
- **Role tags are about reachability, not data.** RLS still narrows what each role
  *sees*; `CA` is center-scoped and finance view-only — keep those `caps.*` gates.
- **Shared widgets** (`AppCard`, `AppListTile`, `AppBadge`, `AppStatTile`,
  `AppEmptyState`, `AppErrorView`, `AppLoading`/`AppSkeletonList`, `AppFormField`,
  `AppDropdownField`, `AppDateField`, `AppSectionHeader`, `AppSnackbar`,
  `BrandWordmark`, `CountBadgeIcon`, `AvatarPicker`, `VerificationBanner`) live in
  [shared/widgets/](apps/mobile/lib/shared/widgets/) — reuse, don't re-implement or restyle.
- If a role tag or tier looks wrong once you're in the code, fix it here in the same pass.
</content>
