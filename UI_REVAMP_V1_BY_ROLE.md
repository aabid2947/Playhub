# UI_REVAMP_V1_BY_ROLE.md — screens & components per role (v1 skin worklist)

> **Companion to [UI_REVAMP_V1.md](UI_REVAMP_V1.md)** (the *how* + design-system).
> **This file is the *who-sees-what* + *which v1 archetype/components apply*** —
> the actionable, role-by-role worklist. Reuses the role→screen map from
> [REVAMP_PROGRESS.md](REVAMP_PROGRESS.md) (still accurate) and adds the **v1 archetype**
> (§4 of the plan: A dashboard · B list · C detail · D form · E finance-hero ·
> F roster · G ranking · H settings · I auth) and the **key v1 widgets** each screen needs.
>
> **Workflow:** do **Phase 0** (foundation) once, then one role top-to-bottom, then log
> in as that role and review. A screen appears under **every** role that reaches it —
> revamp it once, it counts for all. Status: `🟡 Pending` / `🟢 Done`.

---

## Roles & shells

| Code | Role | Shell (home) |
|---|---|---|
| `SA` | super_admin | `SuperAdminHomeShell` |
| `OW` | academy_owner | `OwnerHomeShell` (HomeTab) |
| `AD` | academy_admin | `OwnerHomeShell` (HomeTab) |
| `CA` | **center_admin** | `OwnerHomeShell` (**CenterAdminHomeTab**) — center-scoped, finance view-only |
| `HC` | head_coach | `CoachHomeShell` |
| `CO` | coach | `CoachHomeShell` |
| `TR` | trainer | `CoachHomeShell` |
| `PA` | parent | `ParentHomeShell` |
| `ST` | student | `StudentHomeShell` (= parent surface, RLS-narrowed) |
| `ALL` | every authenticated role | — |
| `Unauth` | signed-out | auth flow |

> Reachability comes from [capabilities.dart](apps/mobile/lib/features/auth/data/capabilities.dart)
> + shell/home/settings gating. RLS narrows *data*; the tag is who reaches the *screen*.
> "view-only" roles see a screen but its mutating actions stay gated off.

---

## Phase 0 — Design-system foundation *(do first; cascades to ALL roles)*

| Unit | File | v1 work |
|---|---|---|
| Tokens | [design_tokens.dart](apps/mobile/lib/core/design_tokens.dart) | Repalette `AppPalette`→orange/navy; add `AppShadows`; align `AppSemanticColors.light`. |
| TS mirror | [colors.ts](colors.ts) · [typography.ts](typography.ts) | Update `lightColors` + heading weights. |
| Theme | [theme.dart](apps/mobile/lib/core/theme.dart) | Orange/navy light scheme; navy ink type (w800 heads); soft-shadow cards; orange nav/FAB/buttons. |
| App entry | [main.dart](apps/mobile/lib/main.dart) | `themeMode: ThemeMode.light`. |
| **New widgets** | `lib/shared/widgets/` | `AppGradientHeader` (+`AppHeroStatRow`,`AppGlassChip`,`AppCircleIconButton`) · `AppFeatureCard` · `AppPillTabs` · `AppAvatar` · `AppLabeledProgress` · `AppMiniBarChart` · `ui_helpers.dart` (`colorFromName`/`initials`/`sportIcon`). Export from `widgets.dart`. |
| **Upgrade widgets** | `lib/shared/widgets/` | `AppCard`(+shadow) · `AppStatTile`(+trendUp) · `AppBadge`(+icon) · `AppSectionHeader`(+icon/action, mixed-case). |
| Restyle | [sport_picker.dart](apps/mobile/lib/features/sports/presentation/sport_picker.dart) | `SportChip`/`SportFilterChipBar` → v1 sport-colored pill + "All" chip. |
| Docs | [SKILLS.md](apps/mobile/SKILLS.md) · [REVAMP.md](REVAMP.md) | Fix violet→orange / drop "both themes" wording. |

---

## 👤 `CA` — center_admin  *(Phase 1 — active; ping after)*

> Frame = `OwnerHomeShell` with `CenterAdminHomeTab`. Reads/writes RLS-narrowed to the
> admin's center; **finance is view-only** (keep `manageFinance`/`viewRevenue`/`manageRefunds`
> gates that hide assign/deactivate/refund). **~30 of these are shared with OW/AD** — doing
> them advances that wave too.

### Wave 1 — frame (first thing on login)
| Screen | Archetype | Key v1 widgets |
|---|---|---|
| [owner_home_shell.dart](apps/mobile/lib/features/home/owner_home_shell.dart) | shell | BrandWordmark appbar, orange `NavigationBar`, `AccountAction`, dismissible `VerificationBanner` |
| [center_admin_home_tab.dart](apps/mobile/lib/features/home/center_admin_home_tab.dart) | **A dashboard** | `AppGradientHeader`+`AppHeroStatRow` (center name as hero sub) · 2-up `AppStatTile` · `AppFeatureCard` grid (today's sessions/attendance/leads/events/inventory) · `AppSectionHeader` |
| [settings_tab.dart](apps/mobile/lib/features/settings/settings_tab.dart) | **H settings** | `AppFeatureCard` manage grid · setting rows · grouped `AppSectionHeader` (keep role gates) |
| [profile_page.dart](apps/mobile/lib/features/auth/presentation/profile_page.dart) | C/D | navy hero + `AppUserAvatar`, editable vs read-only sections |
| [students_tab.dart](apps/mobile/lib/features/students/presentation/students_tab.dart) | **B list** | search + `SportChip` row + count `AppBadge` + `AppAvatar` tiles; gated FAB (`createStudents`) |
| [coaches_tab.dart](apps/mobile/lib/features/coaches/presentation/coaches_tab.dart) | **B list** | same template as students; `manageCoaches` gate |
| [batches_tab.dart](apps/mobile/lib/features/batches/presentation/batches_tab.dart) | **B list** | `SportChip` filter, gradient sport-icon tile, capacity `AppLabeledProgress`+`AppBadge` |

### Wave 2 — home destinations + settings children
| Screen | Archetype | Key v1 widgets |
|---|---|---|
| [todays_sessions_page.dart](apps/mobile/lib/features/attendance/presentation/todays_sessions_page.dart) | **F roster** | session tiles w/ progress ("5/8 marked") badge |
| [admin_attendance_overview.dart](apps/mobile/lib/features/attendance/presentation/admin_attendance_overview.dart) | A/F | `AppStatTile` grid + activity rows (timestamps, load-more) |
| [leads_kanban_page.dart](apps/mobile/lib/features/leads/presentation/leads_kanban_page.dart) | B (kanban) | column headers w/ count `AppBadge`, scannable lead cards; gate create FAB (`manageLeads`) |
| [events_page.dart](apps/mobile/lib/features/events/presentation/events_page.dart) | **B list** | unified status+`SportChip` filter, kind-icon cards, status `AppBadge` |
| [inventory_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_page.dart) | B (tabs) | `AppPillTabs`/TabBar All/Low/Vendors, low-stock `AppBadge`; context FAB gated (`manageInventory`) |
| [centers_tab.dart](apps/mobile/lib/features/centers/presentation/centers_tab.dart) · [centers_page.dart](apps/mobile/lib/features/centers/presentation/centers_page.dart) · [center_form_page.dart](apps/mobile/lib/features/centers/presentation/center_form_page.dart) | B / D | status `AppBadge`, single create path; form grouped sections |
| [sports_settings_page.dart](apps/mobile/lib/features/sports/presentation/sports_settings_page.dart) | H/B | center selector as scope header, `SportChip`, add-sheet (`manageSports`) |
| [audit_log_page.dart](apps/mobile/lib/features/audit/presentation/audit_log_page.dart) | B/C | scannable rows + action `AppBadge`, expand→diff, load-more |

### Wave 3 — detail / form / section screens
| Screen | Archetype | Key v1 widgets |
|---|---|---|
| [student_form_page.dart](apps/mobile/lib/features/students/presentation/student_form_page.dart) | **D form** (+ C detail on edit) | grouped `AppSectionHeader`, `AvatarPicker`, `SportPicker`; embeds fees/discounts/docs sections |
| [student_documents_section.dart](apps/mobile/lib/features/students/presentation/student_documents_section.dart) · [coach_documents_section.dart](apps/mobile/lib/features/coaches/presentation/coach_documents_section.dart) | section | shared doc-section layout, upload affordance, doc tiles |
| [student_bulk_import_page.dart](apps/mobile/lib/features/students/presentation/student_bulk_import_page.dart) · [coach_bulk_import_page.dart](apps/mobile/lib/features/coaches/presentation/coach_bulk_import_page.dart) | D (3-step) | step cards, preview, per-row errors (`createStudents`/`manageCoaches`) |
| [coach_form_page.dart](apps/mobile/lib/features/coaches/presentation/coach_form_page.dart) | **D form** | grouped sections, `SportMultiSelect`, login/invite card |
| [batch_form_page.dart](apps/mobile/lib/features/batches/presentation/batch_form_page.dart) · [schedule_picker.dart](apps/mobile/lib/features/batches/presentation/schedule_picker.dart) | **D form** | Details/Schedule/Capacity groups, day chips, time fields |
| [batch_detail_page.dart](apps/mobile/lib/features/batches/presentation/batch_detail_page.dart) | **C detail** | entity hero, mini-stat row, one enrollment section per status, `BatchChatButton`; fees/discounts view-only for CA |
| [attendance_marking_page.dart](apps/mobile/lib/features/attendance/presentation/attendance_marking_page.dart) | **F roster** | hero summary, toggle rows, pinned Save bar w/ count |
| [performance_history_page.dart](apps/mobile/lib/features/performance/presentation/performance_history_page.dart) · [performance_form_page.dart](apps/mobile/lib/features/performance/presentation/performance_form_page.dart) · [performance_detail_page.dart](apps/mobile/lib/features/performance/presentation/performance_detail_page.dart) | G / D / C | score callout, `AppLabeledProgress` skill bars, single create FAB |
| [lead_detail_page.dart](apps/mobile/lib/features/leads/presentation/lead_detail_page.dart) · [lead_form_page.dart](apps/mobile/lib/features/leads/presentation/lead_form_page.dart) · [lead_convert_sheet.dart](apps/mobile/lib/features/leads/presentation/lead_convert_sheet.dart) | C / D / sheet | header + status badge, activity timeline, titled convert sheet |
| [event_detail_page.dart](apps/mobile/lib/features/events/presentation/event_detail_page.dart) · [event_form_page.dart](apps/mobile/lib/features/events/presentation/event_form_page.dart) · [event_register_sheet.dart](apps/mobile/lib/features/events/presentation/event_register_sheet.dart) | C / D / sheet | status transitions control, registrations section, titled sheet |
| [inventory_item_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_item_page.dart) · [inventory_item_form_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_item_form_page.dart) · [vendors_page.dart](apps/mobile/lib/features/inventory/presentation/vendors_page.dart) · [movement_sheet.dart](apps/mobile/lib/features/inventory/presentation/movement_sheet.dart) | C / D / B / sheet | stock summary card, movements list, reserved-space sheet |
| [sport_picker.dart](apps/mobile/lib/features/sports/presentation/sport_picker.dart) | shared | `SportPicker`/`SportFilterChipBar`/`SportMultiSelect` v1 chips |
| [thread_detail_page.dart](apps/mobile/lib/features/chat/presentation/thread_detail_page.dart) · [batch_chat_button.dart](apps/mobile/lib/features/chat/presentation/batch_chat_button.dart) · [message_parent_button.dart](apps/mobile/lib/features/chat/presentation/message_parent_button.dart) | C (chat) / button | reskinned bubbles, busy/disabled states |
| [student_fees_section.dart](apps/mobile/lib/features/billing/presentation/student_fees_section.dart)* · [student_discounts_section.dart](apps/mobile/lib/features/billing/presentation/student_discounts_section.dart)* · [batch_fees_section.dart](apps/mobile/lib/features/billing/presentation/batch_fees_section.dart)* · [batch_discounts_section.dart](apps/mobile/lib/features/billing/presentation/batch_discounts_section.dart)* | section | shared assignment-section layout, active/inactive `AppBadge` |
| [announcements_page.dart](apps/mobile/lib/features/announcements/presentation/announcements_page.dart) (feed/compose) | B / D | feed list + `AppBadge`; composer audience pickers (`composeAnnouncements`) |

> *Finance sections are **view-only** for `CA` — keep the `manageFinance` gate that hides assign/deactivate.

---

## 👤 `OW`/`AD` — owner + admin  *(Phase 2)*
Everything in `CA` **plus** (mostly archetypes A/B/C/D/E):
[home_tab.dart](apps/mobile/lib/features/home/home_tab.dart) (A) ·
[academy_settings_page.dart](apps/mobile/lib/features/academy/presentation/academy_settings_page.dart) (D) ·
[team_page.dart](apps/mobile/lib/features/users/presentation/team_page.dart) (B) ·
[invite_user_sheet.dart](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart) (sheet) ·
[subscription_page.dart](apps/mobile/lib/features/subscription/presentation/subscription_page.dart) (E) ·
**full billing (E/B/C/D):** [billing_dashboard_page.dart](apps/mobile/lib/features/billing/presentation/billing_dashboard_page.dart) ·
[invoice_list_page.dart](apps/mobile/lib/features/billing/presentation/invoice_list_page.dart) ·
[invoice_detail_page.dart](apps/mobile/lib/features/billing/presentation/invoice_detail_page.dart) ·
[record_payment_page.dart](apps/mobile/lib/features/billing/presentation/record_payment_page.dart) ·
[payments_list_page.dart](apps/mobile/lib/features/billing/presentation/payments_list_page.dart) ·
[refund_form_page.dart](apps/mobile/lib/features/billing/presentation/refund_form_page.dart) ·
[fee_structures_page.dart](apps/mobile/lib/features/billing/presentation/fee_structures_page.dart) ·
[fee_structure_form_page.dart](apps/mobile/lib/features/billing/presentation/fee_structure_form_page.dart) ·
[discount_structures_page.dart](apps/mobile/lib/features/billing/presentation/discount_structures_page.dart) ·
[discount_structure_form_page.dart](apps/mobile/lib/features/billing/presentation/discount_structure_form_page.dart) ·
[financial_reports_page.dart](apps/mobile/lib/features/billing/presentation/financial_reports_page.dart) ·
[announcement_composer_page.dart](apps/mobile/lib/features/announcements/presentation/announcement_composer_page.dart) (D) ·
[kpi_dashboard_page.dart](apps/mobile/lib/features/analytics/presentation/kpi_dashboard_page.dart) (A/G) ·
[report_builder_page.dart](apps/mobile/lib/features/reports/presentation/report_builder_page.dart) (D) ·
[support_page.dart](apps/mobile/lib/features/support/presentation/support_page.dart) (B/C) ·
[threads_page.dart](apps/mobile/lib/features/chat/presentation/threads_page.dart) (B) ·
[notification_center_page.dart](apps/mobile/lib/features/notifications/presentation/notification_center_page.dart) (B) ·
[notification_preferences_page.dart](apps/mobile/lib/features/notifications/presentation/notification_preferences_page.dart) (H). `OW` also: [setup_academy_page.dart](apps/mobile/lib/features/dashboards/setup_academy_page.dart) (I).

## 👤 `HC`/`CO`/`TR` — head_coach / coach / trainer  *(Phase 3)*
[coach_home_shell.dart](apps/mobile/lib/features/coach/presentation/coach_home_shell.dart) (shell) ·
[coach_home_tab.dart](apps/mobile/lib/features/coach/presentation/coach_home_tab.dart) (A) ·
[coach_batches_tab.dart](apps/mobile/lib/features/coach/presentation/coach_batches_tab.dart) (B) ·
[coach_student_page.dart](apps/mobile/lib/features/coach/presentation/coach_student_page.dart) (C) ·
batch_detail · todays_sessions · attendance_marking (F) · performance_* (G/D/C) · chat buttons · thread_detail ·
threads · announcements · notification_center/preferences · events_page · event_detail · [event_results_page.dart](apps/mobile/lib/features/events/presentation/event_results_page.dart) (G) · profile.
(`HC` also: event_form · kpi_dashboard.) `CO`/`HC` record performance; `TR` does not.

## 👤 `PA`/`ST` — parent / student  *(Phase 4)*
[parent_home_shell.dart](apps/mobile/lib/features/parent/presentation/parent_home_shell.dart) /
[student_home_shell.dart](apps/mobile/lib/features/student/presentation/student_home_shell.dart) (shell) ·
[parent_dashboard_tab.dart](apps/mobile/lib/features/parent/presentation/parent_dashboard_tab.dart) (**A**, also the student dashboard via inheritance) ·
announcements · threads · thread_detail · notification_center/preferences · events_page · event_detail · event_register_sheet · profile.

## 👤 `SA` — super_admin  *(Phase 5)*
[super_admin_home_shell.dart](apps/mobile/lib/features/super_admin/presentation/super_admin_home_shell.dart) (shell, `AppBadge('Admin')`) ·
[global_health_page.dart](apps/mobile/lib/features/super_admin/presentation/global_health_page.dart) (A) ·
[academies_page.dart](apps/mobile/lib/features/super_admin/presentation/academies_page.dart) (B) ·
[academy_detail_page.dart](apps/mobile/lib/features/super_admin/presentation/academy_detail_page.dart) (C/E) ·
[plans_page.dart](apps/mobile/lib/features/super_admin/presentation/plans_page.dart) (B) ·
[super_tickets_page.dart](apps/mobile/lib/features/super_admin/presentation/super_tickets_page.dart) (B/C) · profile.

## 👤 `Unauth` — auth flow  *(Phase 2/3, low effort)*
[splash_page.dart](apps/mobile/lib/features/auth/presentation/splash_page.dart) ·
[login_page.dart](apps/mobile/lib/features/auth/presentation/login_page.dart) ·
[signup_page.dart](apps/mobile/lib/features/auth/presentation/signup_page.dart) ·
[forgot_password_page.dart](apps/mobile/lib/features/auth/presentation/forgot_password_page.dart) ·
[set_new_password_page.dart](apps/mobile/lib/features/auth/presentation/set_new_password_page.dart) ·
[auth_scaffold.dart](apps/mobile/lib/features/auth/presentation/auth_scaffold.dart) — all archetype **I**.

---

## Component-usage quick matrix

| v1 widget | Where it shows up |
|---|---|
| `AppGradientHeader` (+hero stat row) | all dashboards (A), detail heros (C), finance heros (E, navy), settings/profile (H, navy), attendance (F) |
| `AppFeatureCard` | dashboards quick-actions, settings "Manage" grid |
| `AppStatTile` (trend) | every dashboard KPI grid, financial_reports, global_health, admin_attendance_overview |
| `AppPillTabs` | invoice/events/inventory status filters, billing |
| `SportChip` / "All" | students/batches/events/leads filters, sport pickers |
| `AppAvatar` (gradient initials) | student/coach/roster/lead/leaderboard tiles |
| `AppLabeledProgress` | skill assessments, batch capacity, collection %, performance |
| `AppBadge` (+icon) | every status pill (invoice/event/lead/ticket/batch/center/attendance) |
| `AppSectionHeader` (+icon) | every grouped detail/dashboard/settings section |
| `AppMiniBarChart` | dashboard attendance/revenue trends (non-fl_chart) |
| `AppCard` (soft shadow) | literally everywhere |

> Mark a screen `🟢 Done` after it matches its archetype + analyze passes. Keep this
> file and [REVAMP_PROGRESS.md](REVAMP_PROGRESS.md) in sync if a role tag turns out wrong.
