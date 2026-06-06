# REVAMP_PROGRESS.md — screen tracker & component map

> **Companion to [REVAMP.md](REVAMP.md).** REVAMP.md is the *how* (per-screen
> brief + shared anatomies). **This file is the *what's-left* + the *where-is-it*:**
> every screen, its effort tier, its status, and **all its nested components** so
> you don't have to grep for them.
>
> **How to use:**
> 1. Pick a `Pending` screen (start with the §5 order in REVAMP.md — shells first).
> 2. Read its REVAMP.md entry for the brief; the **Nested** line here tells you
>    every private widget / embedded section / shared widget it touches — revamp
>    the *whole unit*, not just the page file.
> 3. When the screen is fully revamped + (if asked) analyze-clean, **mark it done:**
>    flip `[ ]`→`[x]`, change `🟡 Pending`→`🟢 Done`, and append your initials/date
>    in the trailing `— done: …` slot. Update the **Progress** counts at the top.

---

## Legend

**Effort tier** — how much layout work the screen carries:
- 🟢 **Easy** — one page, ≤1 private widget, a simple form or flat list. Quick win.
- 🟡 **Medium** — list+filters, multi-section form, or a detail page with several
  nested widgets / one chart.
- 🔴 **Hard** — many nested components (4+), embedded shared sections, multiple
  charts, complex conditional flow, *or* it sets a pattern other screens reuse.

**Status** — `🟡 Pending` or `🟢 Done`.

**Nested** — private `_Widgets` in the same file + embedded shared sections (linked)
+ shared widgets the screen renders. "Hosts:" = a shell/tab that mounts other pages.

---

## Progress

**0 / 84 screens done.** By tier: 🟢 Easy 0/29 · 🟡 Medium 0/38 · 🔴 Hard 0/17.
**Shared units 0 / 5 done** (revamp-once, reused across screens — do these early).

> Update these three lines whenever you mark a screen done.

---

## Shared units — do these first (revamp once, reused everywhere)

Revamping these once fixes many screens. Each parent below says "embeds [X]" — that
[X] lives here. See REVAMP.md §4.4 / §4.6 for the briefs.

- [ ] **`shared docs section`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - Files: [student_documents_section.dart](apps/mobile/lib/features/students/presentation/student_documents_section.dart) + [coach_documents_section.dart](apps/mobile/lib/features/coaches/presentation/coach_documents_section.dart) (near-duplicates → one layout).
  - Nested: `_DocumentTile`, the type-picker sheet. Data: `studentDocumentsProvider` / `coachDocumentsProvider`.
- [ ] **`shared fee-assignment section`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - Files: [batch_fees_section.dart](apps/mobile/lib/features/billing/presentation/batch_fees_section.dart) + [student_fees_section.dart](apps/mobile/lib/features/billing/presentation/student_fees_section.dart).
  - Nested: `_AssignmentTile`, `_AssignSheet`. Data: `assignmentsForBatchProvider` / `assignmentsForStudentProvider`, `feeStructuresProvider`.
- [ ] **`shared discount-assignment section`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - Files: [batch_discounts_section.dart](apps/mobile/lib/features/billing/presentation/batch_discounts_section.dart) + [student_discounts_section.dart](apps/mobile/lib/features/billing/presentation/student_discounts_section.dart).
  - Nested: `_Tile`, `_Sheet`. Data: `batchDiscountAssignmentsProvider` / `studentDiscountAssignmentsProvider`, `discountStructuresProvider`.
- [ ] **`sport_picker.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - File: [sport_picker.dart](apps/mobile/lib/features/sports/presentation/sport_picker.dart). Three widgets: `SportPicker`, `SportFilterChipBar`, `SportMultiSelect`. Normalize their empty states. Used by students/coaches/batches/leads/events/performance.
- [ ] **`schedule_picker.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - File: [schedule_picker.dart](apps/mobile/lib/features/batches/presentation/schedule_picker.dart). Nested: `_TimeField`. Used by batch_form.

---

## §4.1 — App shells & navigation *(do first; sets the frame)*

- [ ] **`owner_home_shell.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [owner_home_shell.dart](apps/mobile/lib/features/home/owner_home_shell.dart). **Defines the canonical shell contract** (AppBar rule + single account entry point) the other shells adopt.
  - Hosts: HomeTab, StudentsTab, CoachesTab, BatchesTab, SettingsTab. Renders: `BrandWordmark`, `VerificationBanner`.
- [ ] **`coach_home_shell.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [coach_home_shell.dart](apps/mobile/lib/features/coach/presentation/coach_home_shell.dart). Hosts: CoachHomeTab, CoachBatchesTab, AnnouncementsPage, ThreadsPage, NotificationCenterPage. Renders: `CountBadgeIcon`.
- [ ] **`parent_home_shell.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [parent_home_shell.dart](apps/mobile/lib/features/parent/presentation/parent_home_shell.dart). Hosts: ParentDashboardTab, AnnouncementsPage, ThreadsPage, NotificationCenterPage. Renders: `CountBadgeIcon`.
- [ ] **`student_home_shell.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [student_home_shell.dart](apps/mobile/lib/features/student/presentation/student_home_shell.dart). Subclass of ParentHomeShell — keep the inheritance.
- [ ] **`super_admin_home_shell.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [super_admin_home_shell.dart](apps/mobile/lib/features/super_admin/presentation/super_admin_home_shell.dart). Hosts: GlobalHealthPage, AcademiesPage, PlansPage, SuperTicketsPage. Replace hand-rolled "Admin" badge with `AppBadge`.
- [ ] **`settings_tab.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [settings_tab.dart](apps/mobile/lib/features/settings/settings_tab.dart). Flat role-gated list → group under `AppSectionHeader`s. No private widgets.
- [ ] **`role_dashboard.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [role_dashboard.dart](apps/mobile/lib/features/dashboards/role_dashboard.dart). **States only** (loading/stub/error) — do NOT touch routing logic. Nested: `_RoleStub`.
- [ ] **`auth_scaffold.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [auth_scaffold.dart](apps/mobile/lib/features/auth/presentation/auth_scaffold.dart). Shared frame for all §4.3 auth pages. Nested: `BrandMark` (gradient "P"), `AuthMessage`, `BrandWordmark`.

---

## §4.2 — Home dashboards / landing tabs *(do early)*

- [ ] **`home_tab.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [home_tab.dart](apps/mobile/lib/features/home/home_tab.dart). The 11-item flat menu → grouped KPI dashboard (reference fix for §3.4).
  - Nested: greeting card, academy card, `_ActionsCard` (11 tiles), two stat rows. Renders: `AppStatTile`, `AppListTile`.
- [ ] **`center_admin_home_tab.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [center_admin_home_tab.dart](apps/mobile/lib/features/home/center_admin_home_tab.dart). Nested: greeting card, stat row, `_ActionCard` (5 tiles).
- [ ] **`coach_home_tab.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [coach_home_tab.dart](apps/mobile/lib/features/coach/presentation/coach_home_tab.dart). Nested: `_StatsRow`, `_AttendanceTrendCard` (fl_chart bar), `_BatchRow`. Hosts a link → TodaysSessionsPage.
- [ ] **`parent_dashboard_tab.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [parent_dashboard_tab.dart](apps/mobile/lib/features/parent/presentation/parent_dashboard_tab.dart). 8 stacked sections + 2 charts + heatmap + inline Razorpay pay. **Also the student dashboard** (shared via shell inheritance).
  - Nested: `SegmentedButton` switcher, `_StudentHeader`, `_UpcomingSessionsCard`, `_BatchesCard`, `_AttendanceCard` (heatmap + bar), `_PerformanceCard` (line), `_MediaGalleryCard`, `_OutstandingCard` (RazorpayCheckout).

---

## §4.3 — Auth & onboarding

- [ ] **`splash_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [splash_page.dart](apps/mobile/lib/features/auth/presentation/splash_page.dart). Renders: `BrandMark`. Add `AppLoading` + status line.
- [ ] **`login_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [login_page.dart](apps/mobile/lib/features/auth/presentation/login_page.dart). Wraps `AuthScaffold`. Renders: `AppFormField`, `AuthMessage`.
- [ ] **`signup_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [signup_page.dart](apps/mobile/lib/features/auth/presentation/signup_page.dart). Wraps `AuthScaffold`. Fix field order + paired-field stacking.
- [ ] **`forgot_password_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [forgot_password_page.dart](apps/mobile/lib/features/auth/presentation/forgot_password_page.dart). Wraps `AuthScaffold`.
- [ ] **`set_new_password_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [set_new_password_page.dart](apps/mobile/lib/features/auth/presentation/set_new_password_page.dart). Wraps `AuthScaffold`. Give new+confirm **independent** obscure toggles.
- [ ] **`profile_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [profile_page.dart](apps/mobile/lib/features/auth/presentation/profile_page.dart). Nested: `_AvatarPreview`. Split editable vs read-only sections.
- [ ] **`setup_academy_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [setup_academy_page.dart](apps/mobile/lib/features/dashboards/setup_academy_page.dart). Align error styling with `AuthMessage`. No private widgets.

---

## §4.4 — People & org management

- [ ] **`students_tab.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [students_tab.dart](apps/mobile/lib/features/students/presentation/students_tab.dart). **Template for coaches/team lists.** Nested: student tiles, filter sheet. Renders: `SportFilterChipBar`, `AppListTile`, `AppBadge`.
- [ ] **`student_form_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [student_form_page.dart](apps/mobile/lib/features/students/presentation/student_form_page.dart). Embeds [StudentFeesSection](apps/mobile/lib/features/billing/presentation/student_fees_section.dart), [StudentDiscountsSection](apps/mobile/lib/features/billing/presentation/student_discounts_section.dart), [StudentDocumentsSection](apps/mobile/lib/features/students/presentation/student_documents_section.dart). Renders: `AvatarPicker`, `SportPicker`, parent-link + student-login tiles, `InviteUserSheet`.
- [ ] **`coaches_tab.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [coaches_tab.dart](apps/mobile/lib/features/coaches/presentation/coaches_tab.dart). Match the students_tab template (add FAB + filter). Nested: `_CoachTile`.
- [ ] **`coach_form_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [coach_form_page.dart](apps/mobile/lib/features/coaches/presentation/coach_form_page.dart). Embeds [CoachDocumentsSection](apps/mobile/lib/features/coaches/presentation/coach_documents_section.dart). Renders: `AvatarPicker`, `SportMultiSelect`, login/invite card, `InviteUserSheet`. Async sports load needs a loading state.
- [ ] **`student_bulk_import_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [student_bulk_import_page.dart](apps/mobile/lib/features/students/presentation/student_bulk_import_page.dart). Nested: preview `DataTable`, result card. 3-step layout.
- [ ] **`coach_bulk_import_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [coach_bulk_import_page.dart](apps/mobile/lib/features/coaches/presentation/coach_bulk_import_page.dart). Same pattern as student import (pipe-separator help).
- [ ] **`centers_tab.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [centers_tab.dart](apps/mobile/lib/features/centers/presentation/centers_tab.dart). Nested: center tiles, `_EmptyState`. Kill duplicate empty-CTA + FAB; add status `AppBadge`.
- [ ] **`centers_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [centers_page.dart](apps/mobile/lib/features/centers/presentation/centers_page.dart). Thin AppBar wrapper around CentersTab — resolve the double-header.
- [ ] **`center_form_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [center_form_page.dart](apps/mobile/lib/features/centers/presentation/center_form_page.dart). Expose model fields (state/pincode/email/…); separate the activate/deactivate action.
- [ ] **`team_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [team_page.dart](apps/mobile/lib/features/users/presentation/team_page.dart). Group members by role. Nested: member tiles. Renders: [InviteUserSheet](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart) (FAB).
- [ ] **`invite_user_sheet.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [invite_user_sheet.dart](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart). Shared sheet (used by team/student/coach). Uses `InvitePreset`. Make assigned role obvious in preset mode.
- [ ] **`academy_settings_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [academy_settings_page.dart](apps/mobile/lib/features/academy/presentation/academy_settings_page.dart). 4 sections (Profile/Hours/Holidays/Invoicing). Nested: `AvatarPicker`, hours time-pickers, holiday chips. Use `AppDateField`/field widgets.
- [ ] **`sports_settings_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [sports_settings_page.dart](apps/mobile/lib/features/sports/presentation/sports_settings_page.dart). Nested: `_CenterSportsList`, `_SportRow`, `_AddSportSheet`. Make center dropdown the clear scope control; add search to the add-sheet.

---

## §4.5 — Training operations

- [ ] **`batches_tab.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [batches_tab.dart](apps/mobile/lib/features/batches/presentation/batches_tab.dart). Renders: `SportFilterChipBar`, batch tiles, capacity `AppBadge`.
- [ ] **`batch_form_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [batch_form_page.dart](apps/mobile/lib/features/batches/presentation/batch_form_page.dart). Embeds [SchedulePicker](apps/mobile/lib/features/batches/presentation/schedule_picker.dart). Renders: `SportPicker`, center/coach dropdowns (stabilize async).
- [ ] **`batch_detail_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [batch_detail_page.dart](apps/mobile/lib/features/batches/presentation/batch_detail_page.dart). 3 repeated enrollment sections → one component. Nested: metadata card, `_EnrollmentSection` (Active/Waitlist/Withdrawn), enroll/transfer sheets. Embeds [BatchFeesSection](apps/mobile/lib/features/billing/presentation/batch_fees_section.dart), [BatchDiscountsSection](apps/mobile/lib/features/billing/presentation/batch_discounts_section.dart). Renders: `BatchChatButton`, `MessageParentButton`.
- [ ] **`todays_sessions_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [todays_sessions_page.dart](apps/mobile/lib/features/attendance/presentation/todays_sessions_page.dart). Nested: `_SessionTile` (progress affordance). Pushes → AttendanceMarkingPage.
- [ ] **`attendance_marking_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [attendance_marking_page.dart](apps/mobile/lib/features/attendance/presentation/attendance_marking_page.dart). Nested: `_DateHeader`, `_StudentRow` (status selector + reserved note area). Human date; visible "mark all"; completion cue.
- [ ] **`admin_attendance_overview.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [admin_attendance_overview.dart](apps/mobile/lib/features/attendance/presentation/admin_attendance_overview.dart). Realtime stream. Nested: `_SummaryRow`, `_Cell`, `_StatusDot`. Add timestamps + "load more".
- [ ] **`performance_form_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [performance_form_page.dart](apps/mobile/lib/features/performance/presentation/performance_form_page.dart). Nested: `_SkillRow` (name+slider+score), evidence/media section. Renders: `SportPicker`. Stabilize the score label; don't crush rows.
- [ ] **`performance_detail_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [performance_detail_page.dart](apps/mobile/lib/features/performance/presentation/performance_detail_page.dart). Score callout + skills list + feedback + media list. Friendly filenames.
- [ ] **`performance_history_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [performance_history_page.dart](apps/mobile/lib/features/performance/presentation/performance_history_page.dart). Nested: `_TrendCard`, `_AssessmentTile`. Single create path (drop duplicate empty CTA).
- [ ] **`coach_batches_tab.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [coach_batches_tab.dart](apps/mobile/lib/features/coach/presentation/coach_batches_tab.dart). Stable trailing area. Renders: `BatchChatButton`.
- [ ] **`coach_student_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [coach_student_page.dart](apps/mobile/lib/features/coach/presentation/coach_student_page.dart). Nested: `_StudentMediaCard`, `_MediaThumb`. Renders: `MessageParentButton`. Flatten card-in-card; tappable contact.

---

## §4.6 — Billing & subscription

- [ ] **`billing_dashboard_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [billing_dashboard_page.dart](apps/mobile/lib/features/billing/presentation/billing_dashboard_page.dart). Hosts (TabBar): InvoiceListPage, FeeStructuresPage, DiscountStructuresPage, PaymentsListPage, FinancialReportsPage. Regroup transactional vs config.
- [ ] **`invoice_list_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [invoice_list_page.dart](apps/mobile/lib/features/billing/presentation/invoice_list_page.dart). Unified filter bar + count + overdue `AppBadge`.
- [ ] **`invoice_detail_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [invoice_detail_page.dart](apps/mobile/lib/features/billing/presentation/invoice_detail_page.dart). Nested: `_SummaryCard`, `_OutstandingActions`, `_PaymentTile`, line-items list. Replace plain-`Text` headers with `AppSectionHeader`.
- [ ] **`record_payment_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [record_payment_page.dart](apps/mobile/lib/features/billing/presentation/record_payment_page.dart). Add confirm + INR cue + success summary.
- [ ] **`payments_list_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [payments_list_page.dart](apps/mobile/lib/features/billing/presentation/payments_list_page.dart). Date-grouped, tappable→invoice, explicit cap/load-more.
- [ ] **`refund_form_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [refund_form_page.dart](apps/mobile/lib/features/billing/presentation/refund_form_page.dart). Nested: `_RefundNote`. Clarify manual vs Razorpay + partial refund.
- [ ] **`fee_structures_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [fee_structures_page.dart](apps/mobile/lib/features/billing/presentation/fee_structures_page.dart). Nested: `_FeeTile`. Status badge + key terms in subtitle.
- [ ] **`fee_structure_form_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [fee_structure_form_page.dart](apps/mobile/lib/features/billing/presentation/fee_structure_form_page.dart). Grouped (Fee/Late fee/Status); gracefully-stacking paired fields; policy help.
- [ ] **`discount_structures_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [discount_structures_page.dart](apps/mobile/lib/features/billing/presentation/discount_structures_page.dart). Nested: `_DiscountTile`. Clean value badge (% vs ₹).
- [ ] **`discount_structure_form_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [discount_structure_form_page.dart](apps/mobile/lib/features/billing/presentation/discount_structure_form_page.dart). Type selector reshapes value field clearly.
- [ ] **`financial_reports_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [financial_reports_page.dart](apps/mobile/lib/features/billing/presentation/financial_reports_page.dart). Nested: `_BigStat`. By-status rows tap → filtered invoice list.
- [ ] **`subscription_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [subscription_page.dart](apps/mobile/lib/features/subscription/presentation/subscription_page.dart). Nested: `_CurrentPlanCard`, `_PlanCard`. Renewal/trial `AppBadge`; comparable plan cards.

---

## §4.7 — Engagement

- [ ] **`leads_kanban_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [leads_kanban_page.dart](apps/mobile/lib/features/leads/presentation/leads_kanban_page.dart). Nested: `_Column`, `_Header`, `_Card`. Responsive columns + scannable cards + per-column empty state.
- [ ] **`lead_detail_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [lead_detail_page.dart](apps/mobile/lib/features/leads/presentation/lead_detail_page.dart). Nested: `_Header`, `_StatusActions`, `_Contact`, `_AddNoteRow`, `_ActivityTile`. Real activity timeline; note composer above keyboard. Renders: [LeadConvertSheet](apps/mobile/lib/features/leads/presentation/lead_convert_sheet.dart).
- [ ] **`lead_form_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [lead_form_page.dart](apps/mobile/lib/features/leads/presentation/lead_form_page.dart). Renders: `SportPicker`. Inline cross-field validation (phone OR email).
- [ ] **`lead_convert_sheet.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [lead_convert_sheet.dart](apps/mobile/lib/features/leads/presentation/lead_convert_sheet.dart). Titled sheet; batch-list loading state; "no batch" placeholder.
- [ ] **`announcements_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [announcements_page.dart](apps/mobile/lib/features/announcements/presentation/announcements_page.dart). Nested: `_AdminList`, `_Feed`. Unify the two views; real detail surface (not bare dialog).
- [ ] **`announcement_composer_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [announcement_composer_page.dart](apps/mobile/lib/features/announcements/presentation/announcement_composer_page.dart). Nested: `_RoleChips`, `_BatchPicker`, `_CenterPicker`. Clear Audience + Channels sections.
- [ ] **`threads_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [threads_page.dart](apps/mobile/lib/features/chat/presentation/threads_page.dart). Nested: `_Tile`. Proper empty preview; unread affordance; stable name resolution.
- [ ] **`thread_detail_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [thread_detail_page.dart](apps/mobile/lib/features/chat/presentation/thread_detail_page.dart). Realtime chat. Nested: `_MessageBubble`, attachment-picker sheet, pending-attachment tray, composer. Day-grouped timestamps; reliable scroll.
- [ ] **`batch_chat_button.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [batch_chat_button.dart](apps/mobile/lib/features/chat/presentation/batch_chat_button.dart). Shared button (compact + full variants). Clear busy/disabled visuals.
- [ ] **`message_parent_button.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [message_parent_button.dart](apps/mobile/lib/features/chat/presentation/message_parent_button.dart). Shared button. Uses `_LinkedParent`, parent-picker sheet. Hide/disable clearly when no parents.
- [ ] **`notification_center_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [notification_center_page.dart](apps/mobile/lib/features/notifications/presentation/notification_center_page.dart). Nested: `_Tile`. Group by date; clear unread affordance; confirm mark-all-read.
- [ ] **`notification_preferences_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [notification_preferences_page.dart](apps/mobile/lib/features/notifications/presentation/notification_preferences_page.dart). 24 toggles → compact category × channel matrix.
- [ ] **`events_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [events_page.dart](apps/mobile/lib/features/events/presentation/events_page.dart). Nested: `_FilterBar`, `_StatusChip`. Renders: `SportFilterChipBar`. Unify the two filter bars; stable card height.
- [ ] **`event_detail_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [event_detail_page.dart](apps/mobile/lib/features/events/presentation/event_detail_page.dart). Nested: `_Header`, `_ManageBar`, `_RegistrationsSection`, `_RegRow`. Renders: [EventRegisterSheet](apps/mobile/lib/features/events/presentation/event_register_sheet.dart). Pushes → EventResultsPage. Status transitions as a control, not a button soup.
- [ ] **`event_form_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [event_form_page.dart](apps/mobile/lib/features/events/presentation/event_form_page.dart). Nested: `_dateRow`. Renders: `SportPicker`. Tidier date/time block; visible publish choice; start<end.
- [ ] **`event_register_sheet.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [event_register_sheet.dart](apps/mobile/lib/features/events/presentation/event_register_sheet.dart). Titled, searchable student picker; explained fee note.
- [ ] **`event_results_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [event_results_page.dart](apps/mobile/lib/features/events/presentation/event_results_page.dart). Nested: `_ResultRow` (3 cramped fields → readable card). Clarify save→generate-cert flow.

---

## §4.8 — Growth, analytics & inventory

- [ ] **`inventory_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [inventory_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_page.dart). Hosts (TabBar): All / Low stock / Vendors. Nested: `_ItemsList`. Context-aware FAB.
- [ ] **`inventory_item_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [inventory_item_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_item_page.dart). Nested: `_StockCard`, `_InlineNote`, movement tiles. Renders: [MovementSheet](apps/mobile/lib/features/inventory/presentation/movement_sheet.dart). Stable stock card; capped movements + load-more.
- [ ] **`inventory_item_form_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [inventory_item_form_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_item_form_page.dart). Grouped sections (Details/Stock & cost/Categorisation).
- [ ] **`vendors_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [vendors_page.dart](apps/mobile/lib/features/inventory/presentation/vendors_page.dart). Nested: `_VendorSheet` (make scrollable + titled). Show active status.
- [ ] **`movement_sheet.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [movement_sheet.dart](apps/mobile/lib/features/inventory/presentation/movement_sheet.dart). Reserve space for conditional recipient dropdowns (no reflow); inline qty validation.
- [ ] **`kpi_dashboard_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [kpi_dashboard_page.dart](apps/mobile/lib/features/analytics/presentation/kpi_dashboard_page.dart). Role-aware. Nested: `CollectionSummaryCard`, `RevenueTrendCard` (bar), `EnrollmentTrendCard` (line), `SportBreakdownCard` (table), `BatchUtilizationCard`, `LeadFunnelCard`. Readable charts + "last updated".
- [ ] **`report_builder_page.dart`** — 🔴 Hard — 🟡 Pending — *— done: —*
  - [report_builder_page.dart](apps/mobile/lib/features/reports/presentation/report_builder_page.dart). Nested: `_FilterEditor`, `_FilterRow`, `_ResultTable`. Clear builder layout; phone-readable results.
- [ ] **`audit_log_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [audit_log_page.dart](apps/mobile/lib/features/audit/presentation/audit_log_page.dart). Nested: `ExpansionTile` rows, `_DiffRow`, `_Json`. Scannable rows + action `AppBadge` + "load more".
- [ ] **`support_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [support_page.dart](apps/mobile/lib/features/support/presentation/support_page.dart). Nested: `_NewTicketSheet` (make scrollable), `_TicketThreadPage`. Status/priority `AppBadge`; clearer thread.

---

## §4.9 — Super-admin (platform)

- [ ] **`global_health_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [global_health_page.dart](apps/mobile/lib/features/super_admin/presentation/global_health_page.dart). Nested: `GlobalRevenueCard`, status `AppStatTile` grid. Handle odd tile count; status counts drill down.
- [ ] **`academies_page.dart`** — 🟢 Easy — 🟡 Pending — *— done: —*
  - [academies_page.dart](apps/mobile/lib/features/super_admin/presentation/academies_page.dart). Status `AppBadge`; styled search; **confirm before toggling is_active**.
- [ ] **`plans_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [plans_page.dart](apps/mobile/lib/features/super_admin/presentation/plans_page.dart). Nested: `_PlanSheet` (stack limit fields; clarify "unlimited"). Confirm on delete.
- [ ] **`super_tickets_page.dart`** — 🟡 Medium — 🟡 Pending — *— done: —*
  - [super_tickets_page.dart](apps/mobile/lib/features/super_admin/presentation/super_tickets_page.dart). Nested: `_TicketDetailPage`. Replace priority `CircleAvatar` with `AppBadge`; status control shows current state.

---

## Notes

- **A "screen" = the page + all its nested components.** The `Nested:` line is your
  checklist of what to touch — private `_Widgets` live in the same file; embedded
  sections and shared widgets are linked.
- **Shared widgets** (`AppCard`, `AppListTile`, `AppBadge`, `AppStatTile`,
  `AppEmptyState`, `AppErrorView`, `AppLoading`/`AppSkeletonList`, `AppFormField`,
  `AppDropdownField`, `AppDateField`, `AppSectionHeader`, `AppSnackbar`,
  `BrandWordmark`, `CountBadgeIcon`, `AvatarPicker`, `VerificationBanner`) are the
  design system in [shared/widgets/](apps/mobile/lib/shared/widgets/) — **reuse, don't
  re-implement, don't restyle.**
- If a screen turns out harder/easier than tagged, **re-tag it** and adjust the
  Progress counts — the tier is a planning aid, not a contract.
</content>
