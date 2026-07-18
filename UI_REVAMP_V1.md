# UI_REVAMP_V1.md — PlayHub mobile "v1 Sports-Light" visual revamp

> **What this is.** The authoritative plan for re-skinning the entire PlayHub
> Flutter app (`apps/mobile`) to the **v1 UI concept the client approved**
> (`ui_demo/v1`, on the `ui-demo` branch). It covers the design-system migration,
> the component vocabulary, the per-archetype treatment, and the role-by-role
> rollout. **Companion:** [UI_REVAMP_V1_BY_ROLE.md](UI_REVAMP_V1_BY_ROLE.md) is the
> who-sees-what screen+component inventory (the worklist).
>
> **Predecessor docs.** [REVAMP.md](REVAMP.md) / [REVAMP_PROGRESS.md](REVAMP_PROGRESS.md)
> drove a **layout/IA** revamp that is largely complete (good list/detail/form/dashboard
> anatomy already exists). They were written under a *now-reversed* guardrail
> ("do NOT change color or typography — violet, light+dark are locked"). **This
> doc supersedes that guardrail** (see §1). The layout anatomies they define are
> still correct and reused here; only the *skin* changes.

---

## 0. The decision (signed off)

The client liked **`ui_demo/v1`** — the **"Sports-Light"** language:

- **Energetic orange `#FF6A2C`** leads every call-to-action; **deep navy `#0F2540`**
  is the ink for headings/high-contrast text; a broadcast-**blue accent `#1763E0`**
  is used sparingly. Clean near-white surfaces (`#F4F7FB` page / white cards).
- **Hero gradient bands** (orange brand gradient, or a navy gradient) anchor the top
  of dashboards and detail/section landings, with white-on-gradient content and a
  floating summary card that overlaps the band.
- **Colorful "feature cards"** (gradient-icon quick actions), **KPI stat tiles with
  trend pills**, **pill-tab** segmented filters, **sport-colored chips**, **gradient
  avatars**, and **soft-shadowed cards** (not just hairline outlines).
- **Light theme only** — the demo ships no dark theme (per client).

**Two load-bearing reversals from the old locked theme** (confirmed with the user
2026-06-09):

1. **Brand recolor: violet `#9933FF` → orange `#FF6A2C` + navy.** This overturns
   the 2026-06-06 "theme is locked (violet)" change-log entry. The new locked source
   of truth is the v1 palette below, mirrored into
   [colors.ts](colors.ts) · [design_tokens.dart](apps/mobile/lib/core/design_tokens.dart) ·
   [theme.dart](apps/mobile/lib/core/theme.dart).
2. **Light-only.** Drop device-following dark mode; pin `themeMode: ThemeMode.light`.
   The dark `ColorScheme`/`AppSemanticColors.dark` code stays in the tree (dormant)
   so nothing that reads them crashes, but no screen renders dark.

> Update [apps/mobile/SKILLS.md](apps/mobile/SKILLS.md) §0–§6 and
> [REVAMP.md](REVAMP.md) §1.1 in the same pass — their "violet / both themes / don't
> touch color" wording is now stale. (Tracked as a Phase-0 task.)

---

## 1. Guardrails for the v1 revamp

**Still load-bearing — do NOT break:**

1. **Shared widgets stay thin wrappers over Material primitives** so
   `find.byType(Card/ListTile/TextField)` widget-test finders resolve. New v1
   widgets (`AppGradientHeader`, `AppFeatureCard`, `AppPillTabs`) are *additive*;
   they don't replace `AppCard`/`AppListTile`/`AppFormField`.
2. **UI never offers what RLS rejects.** Every capability gate
   ([capabilities.dart](apps/mobile/lib/features/auth/data/capabilities.dart),
   `ref.watch(capabilitiesProvider).manageX`) stays exactly where it is. A coat of
   paint never widens access. center_admin stays center-scoped + finance view-only.
3. **No new architecture.** No `freezed`/codegen, no `@riverpod`, no state lib, no
   service layer, no new heavyweight dependency. Charts stay dependency-free
   container/`CustomPaint` bars like the demo (don't pull `fl_chart` into new screens;
   leave existing `fl_chart` usages alone unless a screen is being reworked anyway).
4. **No data-flow / backend changes.** Pure presentation. Keep every provider read,
   `ref.invalidate(...)` after writes, RPC/edge-fn call. Anything that would need a
   new query/column → **flag, don't build.**
5. **Tokens, not literals.** Pull every color/space/radius/shadow/type from
   `design_tokens.dart` + the theme. The demo hard-codes values (it's a throwaway);
   the real app must not — we *port the demo's values into the token layer* and then
   consume tokens. A raw `Color(0xFF…)`/`EdgeInsets.all(28)`/`fontSize: 18` in a
   screen is a regression.
6. **Analyze-clean by construction** (`very_good_analysis`): trailing commas,
   `const` where possible, `.withValues(alpha:)` not `withOpacity`, no raw-type/cast
   lints.

**Reversed (now allowed, where it was forbidden before):**

- ✅ Restyle colors → to the v1 orange/navy palette (via tokens/theme only).
- ✅ Adjust the type scale to v1 weights (heavier `w800` headlines, navy ink).
- ✅ Use **soft shadows** on cards (the demo's `Shadows.card`), not only outlines.
- ✅ Use **gradient hero bands** as a primary layout device on dashboards/detail.
- ✅ Drop dark-mode rendering.

---

## 2. The v1 design tokens (port these into the token layer)

Source of truth becomes these values (from `ui_demo/v1/lib/theme/tokens.dart`).

### Color (`AppPalette` in design_tokens.dart, mirrored in colors.ts `lightColors`)
| Token | Value | Use |
|---|---|---|
| `brandPrimary` (orange) | `#FF6A2C` | every CTA, primary button, selected, nav selection, FAB |
| `brandPrimaryDark` | `#F4511E` | pressed / gradient end |
| `brandPrimarySoft` | `#FFF1EA` | nav indicator, brand-tint backgrounds |
| `ink` (navy) | `#0F2540` | headings / high-contrast (`onSurface`) |
| `inkSoft` | `#1B3A5C` | navy gradient end |
| `accent` (blue) | `#1763E0` | links / secondary highlight (`secondary`) · `accentSoft #E9F1FE` |
| `textPrimary` | `#12283F` | body primary |
| `textSecondary` | `#5B6B7F` | `onSurfaceVariant` |
| `textMuted` | `#8A99AC` | captions/meta |
| `background` | `#F4F7FB` | scaffold page |
| `surface` | `#FFFFFF` | cards |
| `surfaceAlt` | `#EFF4FA` | inset/segment track, tinted icon bg |
| `border` | `#E6EDF5` · `divider #EDF1F7` | hairlines |
| `success` | `#16A34A` (soft `#E7F6EC`) | semantic success (note: v1 darkens from `#22C55E`) |
| `warning` | `#F59E0B` (soft `#FEF3E2`) | semantic warning |
| `danger` | `#EF4444` (soft `#FDECEC`) | semantic danger |
| `info` | `#1763E0` (soft `#E9F1FE`) | semantic info |
| `brandGradient` | `[#FF8A4C, #FF6A2C, #F4511E]` | hero bands, brand marks, peak chart bars |
| `navyGradient` | `[#173B62, #0F2540]` | billing/finance + "More"/profile heros |
| `categorySwatch` | `[#FF6A2C, #1763E0, #16A34A, #9333EA, #EA580C, #0EA5E9]` | per-sport / category accents |

### Spacing / radius / shadow / type
- **Spacing** (`AppSpacing`, keep names): v1 uses `4 8 12 16 20 28 40`. Current app is
  `4 8 12 16 24 32 48`. **Keep the app's existing `AppSpacing` scale** (screens already
  use it) — do *not* renumber tokens; the visual difference is negligible and renumbering
  would silently reflow 150 files. Only `xl` differs (24 vs demo's 20) — acceptable.
- **Radius** (`AppRadius`): demo `sm10 md14 lg20 xl26 pill`. App is `sm8 md12 lg16 xl20 xxl28 pill`.
  **Keep the app's scale**; cards still read as "lg-rounded". (Optional: bump `lg`→16→18 later
  if the client wants rounder cards — defer.)
- **Shadow** — *new* token class `AppShadows` (port demo's `Shadows`): `card`
  (the soft `0x0F0F2540` blur-18 + hairline), `raised` (orange-tinted), `floating`
  (for pinned bottom bars / overlapping hero cards). Cards gain `card` in light.
- **Type** (`_textTheme` in theme.dart): adopt v1 weights — `displaySmall` w800,
  `headlineMedium/Small` w800/w700, navy ink color on headings, body at navy
  `textPrimary`/`textSecondary`. Keep Inter. Don't fight the scale in screens.

---

## 3. Component vocabulary → shared/widgets mapping

The demo's `ui_kit.dart` defines the vocabulary. Map each to `lib/shared/widgets/`
(**add** the new ones to the barrel `widgets.dart`; **upgrade** the existing ones so
the change cascades app-wide):

| v1 component (`ui_kit.dart`) | shared/widgets action | Notes |
|---|---|---|
| `AppCard` (soft shadow + radius) | **Upgrade** [app_card.dart](apps/mobile/lib/shared/widgets/app_card.dart): add optional `shadow` (default true in light) via new `AppShadows.card`; keep it a real `Card`. | Cascades to every card in the app. |
| `GradientHeader` | **Add** `app_gradient_header.dart` → `AppGradientHeader({child, colors, height})` | Hero band; default `brandGradient`, navy variant for finance/profile. White content; bottom `lg` radius. |
| `FeatureCard` | **Add** `app_feature_card.dart` → `AppFeatureCard({title, subtitle, icon, tint, onTap, badge})` | Colorful gradient-icon quick-action tile (the "nice feature cards"). Built on `AppCard`. |
| `StatTile` (trend pill) | **Upgrade** [app_stat_tile.dart](apps/mobile/lib/shared/widgets/app_stat_tile.dart): add `trendUp:bool` (down → danger tone + `trending_down`); `color`/tint already supported. | Already an `AppStatTile`. |
| `StatusBadge` (+ icon, `brand` tone) | **Upgrade** [app_badge.dart](apps/mobile/lib/shared/widgets/app_badge.dart): add optional `icon`. `brand` tone already exists. | Map domain status → tone in one helper per feature. |
| `SectionHeader` (icon + action) | **Upgrade** [app_section_header.dart](apps/mobile/lib/shared/widgets/app_section_header.dart): add optional `icon` + `actionLabel`/`onAction`; switch to v1 `titleMedium` (mixed-case, navy) **instead of** the current UPPERCASE `labelMedium`. | Cascades app-wide — verify a couple of screens after. |
| `PillTabs` | **Add** `app_pill_tabs.dart` → `AppPillTabs({tabs, index, onChanged})` | Segmented in-body filter (invoices, events, etc.). |
| `SportChip` + "All" chip | **Align** the existing `SportFilterChipBar`/`SportChip` in [sport_picker.dart](apps/mobile/lib/features/sports/presentation/sport_picker.dart) to v1 styling (sport-colored pill + `sportIcon`). Add an "All" pill (ink-filled when selected). | Reuse existing widget; restyle only. |
| `Avatar` (gradient initials) | **Add** `app_avatar.dart` → `AppAvatar(name, {size, color})` (gradient initials, deterministic color via `colorFromName`). Keep `AppUserAvatar` (photo+fallback) for the account/profile surfaces. | Use `AppAvatar` for student/coach/roster tiles where there's no photo. |
| `LabeledProgress` | **Add** `app_labeled_progress.dart` → `AppLabeledProgress({label, value, trailing, color})` | Skill bars, capacity, collection %. |
| `colorFromName` / `initials` / `sportIcon` | **Add** to a small `lib/shared/widgets/ui_helpers.dart` (or `core`) | Deterministic sport/category color + icon; reused by avatar/chip/tiles. |
| Mini bar chart (`_BarChart`, `_LineBars`) | **Add** `app_mini_bar_chart.dart` → `AppMiniBarChart({values, labels, peakHighlight})` (dependency-free) | For dashboard trends without `fl_chart`. Existing `fl_chart` cards (kpi_dashboard, coach_home) keep their charts but get recolored + a labeled/“last updated” frame. |
| `EmptyHint` | Map to existing `AppEmptyState` | No new widget. |

**Hero-internal pieces** (circle icon button, glass chip, hero stat row/divider,
floating overlap card) are simple enough to live as private `_Widgets` *inside*
`AppGradientHeader` or the screen — don't over-abstract. Provide `AppGradientHeader`
helpers: `AppHeroStatRow` (the translucent summary card) + `AppGlassChip` +
`AppCircleIconButton` so dashboards/detail reuse them.

---

## 4. Screen archetypes (build to these)

Every screen maps to one of these. The §3 layout anatomy from the old REVAMP.md
still holds; this layers the v1 skin on top.

**A. Dashboard / home** (home_tab, center_admin_home_tab, coach_home_tab, parent_dashboard_tab, global_health):
`AppGradientHeader` greeting hero (avatar + notif bell + a translucent floating
`AppHeroStatRow` of 2–3 headline metrics) → overlap upward `-AppSpacing.lg` →
2-up `AppStatTile` KPI grid (with trend pills) → **`AppFeatureCard` quick-actions
grid** (colorful, gated) → a labeled trend chart card → grouped `AppSectionHeader`
sections (Today's sessions / activity / etc.). *Reference: demo `admin_dashboard.dart`.*

**B. List** (students_tab, coaches_tab, batches_tab, centers_tab, events_page, invoice_list, leads, inventory, threads, announcements, team):
In-body header row (`headlineSmall` title + count `AppBadge`) → search field →
horizontal sport/status chip row (`SportChip` + "All") → `ListView` of `AppCard`
tiles (gradient `AppAvatar`/tinted sport icon → title → one tight subtitle → trailing
metric/`AppBadge`) → single gated `FloatingActionButton.extended` (orange).
*Reference: demo `students_screen.dart`, `batches_screen.dart`.*

**C. Detail** (student detail via student_form view, batch_detail, lead_detail, invoice_detail, event_detail, inventory_item, performance_detail, coach_student, academy detail):
Sport/entity-colored `AppGradientHeader` (back + edit/more circle buttons, big
`AppAvatar`, name, sub, glass chips) → floating 3-up mini-stat row overlapping the
band → `AppSectionHeader(icon:)` sections in `AppCard`s (skill bars via
`AppLabeledProgress`, info rows with leading icon + value + dividers) → bottom action
row (Outlined secondary + Filled primary). *Reference: demo `student_detail_screen.dart`.*

**D. Form** (student_form, coach_form, batch_form, *_structure_form, event_form, lead_form, center_form, record_payment, refund, movement):
`Form` → `ListView` padded `AppSpacing.lg` → `AppFormField`s grouped under
`AppSectionHeader`s → pinned bottom full-width primary `FilledButton` (busy → inline
spinner). Keep edit-only sections below a divider. (Skin only; structure already done.)

**E. Finance hero** (billing_dashboard, financial_reports, subscription, invoice_detail summary):
**Navy** `AppGradientHeader` with a big ₹ figure + trend `AppBadge` + 3 translucent
hero chips (overdue/pending/collected) → revenue trend chart card → `AppPillTabs`
status filter → invoice/payment `AppCard` rows. *Reference: demo `billing_screen.dart`.*

**F. Attendance / roster** (attendance_marking, todays_sessions, admin_attendance_overview):
`AppGradientHeader` with session title + present/absent/left summary → roster header
("Roster · N" + "All present" action) → roster rows (`AppAvatar` + name + present/absent
toggle squares) → pinned bottom `floating`-shadow Save bar with count. *Reference:
demo `attendance_screen.dart`.*

**G. Performance / ranking** (performance_history, kpi sport breakdown, leaderboards):
Dark navy "podium"/summary card (top-3 or headline) → `AppLabeledProgress` skill
averages → ranked `AppCard` rows with score chips/stars. *Reference: demo `performance_screen.dart`.*

**H. Settings / "more"** (settings_tab, notification_preferences, sports_settings, audit):
Navy `AppGradientHeader` profile hero → `AppFeatureCard` "Manage" grid (gated) →
`AppCard` of setting rows (leading tinted icon + label + optional trailing badge +
chevron) under `AppSectionHeader`s → danger-outlined Sign-out. *Reference: demo `more_screen.dart`.*

**I. Auth** (splash, login, signup, forgot/reset, setup_academy):
`auth_scaffold` reskinned: brand mark on a soft surface, orange primary button,
navy ink headings. Light only.

---

## 5. Rollout — Phase 0 first, then by role

> **Order = leverage** + the user's instruction: **center_admin first**, then ping.

### Phase 0 — Design-system foundation *(must land first; sequential; analyze-clean)*
The whole app inherits color from the theme, so Phase 0 **recolors every screen at
once** (orange surfaces/buttons/nav) even before its layout is reworked — an
acceptable intermediate state. Tasks:
1. `design_tokens.dart` — repalette `AppPalette` to §2; add `AppShadows`; align
   `AppSemanticColors.light` (success `#16A34A`); keep dark variants (dormant).
2. `colors.ts` — update `lightColors` to the v1 palette (TS mirror for web/parity).
   `typography.ts` — bump heading weights to match (low risk).
3. `theme.dart` — orange/navy light `ColorScheme`; navy ink text; soft-shadow card
   theme; orange `NavigationBar`/FAB/buttons; v1 type weights.
4. `main.dart` — `themeMode: ThemeMode.light`.
5. Add the new shared widgets (§3): `AppGradientHeader` (+ `AppHeroStatRow`,
   `AppGlassChip`, `AppCircleIconButton`), `AppFeatureCard`, `AppPillTabs`,
   `AppAvatar`, `AppLabeledProgress`, `AppMiniBarChart`, `ui_helpers.dart`; **upgrade**
   `AppCard`, `AppStatTile`, `AppBadge`, `AppSectionHeader`; restyle `SportChip`.
   Export the new ones from `widgets.dart`.
6. Update `SKILLS.md` + `REVAMP.md` §1 wording (violet→orange, drop "both themes").
7. `flutter analyze` (offer to run — see §7).

### Phase 1 — center_admin *(this session; then ping)*
The full center_admin-reachable surface (see [UI_REVAMP_V1_BY_ROLE.md](UI_REVAMP_V1_BY_ROLE.md)
`CA` set). Signature surface = `center_admin_home_tab` (archetype A) inside
`owner_home_shell`. Many of these screens are **shared with owner/admin** — revamping
them advances the OW/AD wave too (expected). Keep center-scope + finance-view-only gates.

### Phase 2+ — remaining roles (later sessions, after sign-off)
owner/admin (home_tab + full billing + comms/reports) → coach/head_coach/trainer →
parent/student → super_admin → auth. Each: do the role's set, then log in as that
role and review the surface coherently.

---

## 6. Risks & open items
- **Shared-screen blast radius.** center_admin shares ~30 screens with owner/admin;
  restyling them changes both surfaces. Intended, but means "center_admin done" ≈
  "owner/admin mostly done" too. Tracked in the by-role doc.
- **`AppSectionHeader` case change** (UPPERCASE → mixed-case + icon) touches every
  screen that uses it. Visual-only; verify a couple of screens.
- **Soft shadows on `AppCard`** change the whole app's card feel. Matches v1.
- **Dark-mode dormancy.** Code paths reading `AppSemanticColors.dark` / dark scheme
  stay but never execute. If a future dev re-enables dark, it'll be stale — note it.
- **fl_chart screens** (kpi_dashboard, coach_home_tab) keep their charts; only recolor
  + frame. Don't rewrite them into `AppMiniBarChart` unless reworking anyway.
- **Demo hard-codes; app tokenizes.** Never copy a demo `Color(0xFF…)` into a screen —
  route it through `AppPalette`/`colorFromName`.

## 7. Verification
Per repo memory, mobile `flutter analyze`/`test` run **only when the user asks**.
Code is analyze-clean by construction. **Because Phase 0 reskins the whole app**, a
single `flutter analyze` (and a glance at the role dashboards) is strongly advised —
offered to the user at the center_admin checkpoint. Widget-type finders must still
resolve (shared widgets stay real `Card`/`ListTile`/`TextField`).

## 8. Definition of done (per screen)
- [ ] Matches its §4 archetype; uses the v1 shared widgets; no bespoke re-implementation.
- [ ] All color/space/radius/shadow/type from tokens — no literals.
- [ ] Every capability gate + provider read/write + `ref.invalidate` preserved.
- [ ] Loading/error/empty via `AppLoading`/`AppSkeletonList`/`AppErrorView`/`AppEmptyState`.
- [ ] Light-only correct; no `Colors.black/white` for text/surfaces (use scheme/tokens).
- [ ] analyze-clean by construction; type finders resolve.
