# REVAMP.md — PlayHub mobile layout & structure revamp

> **What this is.** A screen-by-screen worklist for taking the PlayHub Flutter app
> (`apps/mobile`) from *"looks like a project"* to *"looks like production"* — by
> fixing **layout, structure, placement, information hierarchy, and navigation**.
> Every screen below has its own task; pick one, follow the per-screen process, ship it.
>
> **Audience.** A future Claude told *"revamp screen X."* This doc gives you the
> screen's job, the data it renders (and exactly which files reveal that data's
> shape), what's wrong with the current layout, and the target structure to build.
>
> **Companions (read first, once):**
> [SKILLS.md](apps/mobile/SKILLS.md) — the visual playbook ·
> [design-system reference](apps/mobile/lib/shared/widgets/README.md) ·
> [project rules](CLAUDE.md) · [file map](repo_structure.md).

---

## 0. The mission, in one paragraph

The look is **calm, dense, trustworthy** — an operations tool people use all day.
The brand, color, and type are already finalized and **locked**. The remaining gap
is *structural*: screens are flat undifferentiated lists, forms are one long scroll
with no grouping, dashboards dump 11-item menus, detail pages read like debug
output, lists lack search/filter, and the same job (list, form, detail, sheet) is
solved a different way on every screen. **This revamp makes the layout system
consistent and the information hierarchy deliberate** — nothing more, nothing less.

---

## 1. Hard guardrails — do NOT cross these

These turn a revamp into a bug. They are non-negotiable.

1. **Color/type now follow the v1 skin (this doc's "don't touch color" rule is
   SUPERSEDED as of 2026-06-09).** The authoritative skin spec is
   [UI_REVAMP_V1.md](UI_REVAMP_V1.md): the brand is **orange `#FF6A2C` + navy
   `#0F2540`**, **light-only**. `colors.ts` / `design_tokens.dart` / `theme.dart`
   remain the single source of truth — never hard-code a `Color(0xFF…)`,
   `EdgeInsets.all(32)`, or `fontSize: 18`; consume tokens. This doc's layout
   anatomies (§3) are still correct and reused; only the skin changed.
   > ⚠️ Wherever this doc still says "violet" / "both themes ship", it's stale —
   > read orange + navy / light only.

2. **No new architecture for a layout change.** No `freezed`/codegen, no
   `@riverpod`, no state-management lib, no service layer, no new dependency.
   Match the hand-written model/provider idiom already in the file (see
   [student_providers.dart](apps/mobile/lib/features/students/data/student_providers.dart)).

3. **Shared widgets stay thin wrappers over Material primitives.** Keep using
   `AppCard`/`AppListTile`/`AppFormField`/etc. so `find.byType(Card/ListTile/TextField)`
   in widget tests still resolves. Never replace an `AppCard` with a bespoke
   `Container` that no longer renders a real `Card`.

4. **Preserve capability gates and provider wiring.** Visibility of mutating
   actions is gated by
   [capabilities.dart](apps/mobile/lib/features/auth/data/capabilities.dart)
   (`ref.watch(capabilitiesProvider).manageX`). RLS is the real gate; the UI must
   mirror it. When you move a gated action, **the gate moves with it.** Keep every
   `ref.invalidate(...)` after a write, every provider read, every RPC call.

5. **Don't change data flow or backend.** This is layout only. No new columns, no
   migration, no provider semantics change. If a screen genuinely needs a new
   query to be laid out well, **flag it in your plan and stop** — don't invent it.

6. **Light + dark both ship.** Use `colorScheme.*` and `AppSemanticColors.of(context)`;
   never `Colors.black/white` for text/surfaces.

---

## 2. The per-screen process — follow this every time

For the screen you were handed:

1. **Read the data first.** Open the screen's `data/` files named in its entry
   below — the **model** (`*.dart`, the `fromMap` factory shows every field the
   backend sends) and the **providers** (`*_providers.dart`, shows what's fetched,
   filtered, and written). For deeper backend truth, open the migration named in
   the entry under `supabase/migrations/`. **You cannot lay out data you don't
   understand** — know every field, which are nullable, which are computed.

2. **Plan the layout.** Write a short plan: the new top-to-bottom structure, what
   gets grouped under which section, what moves to a sheet vs. stays inline, how
   the list/detail/form anatomy (§3) applies, and which problems from the entry
   you're fixing. Confirm no guardrail is touched.

3. **Implement** using the shared widgets and the anatomies in §3. Reuse the
   cross-cutting patterns so the screen feels like the rest of the app.

4. **Verify.** Per the repo memory, **only run `flutter analyze` / `flutter test`
   if the user asks** — but your code must be analyze-clean by construction
   (trailing commas, `const`, `.withValues(alpha:)` not `withOpacity`, no magic
   numbers). Type-based finders must still resolve.

---

## 3. The production layout system — apply everywhere

This is what makes 65 screens feel like one app. Most screens fail these; this is
where the lift is. Build to these anatomies unless the screen entry says otherwise.

### 3.1 List screen anatomy
`Scaffold` → optional **pinned filter/search bar** → `body: async.when(...)`:
- `loading:` → `AppSkeletonList()` (never a bare `CircularProgressIndicator`).
- `error:` → `AppErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(...))`.
- `data:` empty → `AppEmptyState(...)`; else `RefreshIndicator` → `ListView.separated`
  of `AppListTile`.
- **One** create path: a single `FloatingActionButton.extended`, **gated** by
  `caps.*`. Kill the duplicate "empty-state button + FAB" pattern — empty state's
  CTA and the FAB must not both create.
- **Search/filter belongs in one place.** If a list has a status filter *and* a
  sport chip bar (students, events, invoices), unify them into one filter row;
  don't orphan one above the other. Show a result count ("12 students").
- **Tile rhythm is consistent across the app.** A list tile is: tinted leading
  icon/avatar → title (primary) → one tight subtitle line → trailing status
  `AppBadge` or count. Don't cram sport + skill + parent + phone onto one wrapping
  line — pick the two that matter, drop the rest to the detail page.

### 3.2 Detail screen anatomy
`Scaffold` (AppBar = entity name, primary actions as AppBar actions/overflow) →
`ListView` padded `AppSpacing.lg`:
- **Header card** first: identity + key status badges, the 2–3 facts that matter.
- Then **`AppSectionHeader`-delimited sections**, each a card or grouped list.
  Never plain `Text("Payments")` headers — use `AppSectionHeader`. Never render a
  detail page as a flat run of `Text` (the "debug dump" smell in invoice/audit).
- Repeated identical sections (e.g. batch detail's Active/Waitlist/Withdrawn) get
  **one** section component with a status sub-header and a count — not three
  copy-pasted blocks.
- Money/score/primary metric gets a real visual callout (headline value in a card),
  not a wrapping `Row` of three equal cells that collapses on narrow screens.

### 3.3 Form screen anatomy
`Form(key:)` → `ListView` padded `AppSpacing.lg` → fields spaced `AppSpacing.md`,
**grouped under `AppSectionHeader`s by meaning** (contact together, training
together, address together) → a **pinned/bottom full-width primary button** (busy →
inline spinner; disable fields or the button while saving to stop double-submit).
- **Required vs optional is visible at a glance** — consistent marker, applied the
  same way on every form (don't asterisk on one screen and not the next).
- **Create and edit should feel structurally the same.** When edit reveals extra
  sections (documents, fees, logins), present them as clearly-separated sections
  *below* a divider, labeled, so the page doesn't feel like a different screen.
- Side-by-side field rows (base+tax, start+end, first+last) must **wrap or stack
  gracefully** on narrow screens — don't let inputs crush to unusable widths.
- Validate cross-field rules inline where possible (end-after-start, phone-OR-email),
  not only on submit.

### 3.4 Dashboard / home anatomy
Greeting/hero first → a 2-up grid of `AppStatTile` KPIs → **grouped** action lists
under `AppSectionHeader`s by theme (Daily ops · Money · Growth · Comms) — **never
one flat 11-item menu**. Primary actions (today's sessions, attendance) sit above
tertiary ones (notifications). Charts get a labeled section, a "last updated" cue,
and readable axes; don't lean on touch-only tooltips for the only labels.

### 3.5 Sheet vs. full page — pick deliberately
- **Bottom sheet** = a short, single-purpose action (pick one thing, confirm,
  one or two fields): enroll, transfer, register, invite, movement, vendor quick-edit.
  Always give the sheet a **title row** and make it **scrollable** with keyboard
  insets so content never clips. Bound its height.
- **Full page** = anything with grouped sections, multiple required fields, or its
  own lifecycle (compose announcement, fee structure, event). If a "sheet" has 3+
  sections, promote it to a page.
- Be consistent: don't make the same kind of action a sheet on one screen and a
  page on another.

### 3.6 States, density & a11y (always)
- Every async surface has loading (`AppSkeletonList`/`AppLoading`), error
  (`AppErrorView` + retry), and empty (`AppEmptyState`) — no `"—"`/`"…"`/`"(unknown)"`
  filler as an empty state.
- **Reserve space for conditional UI** (attendance notes field, movement
  recipient dropdowns) so toggling status doesn't make the layout jump.
- Long lists (payments, audit, academies) need an explicit **cap + "load more"**
  cue, or say in the plan it's deferred — silent `.take(40)`/`limit 200` reads as
  "everything" when it isn't.
- Tap targets ≥ 48px; icon-only buttons get `tooltip`; status never encoded in
  color alone (pair with text/icon — `AppBadge` already does).
- Status → `AppBadge(tone:)` via one mapping helper per domain. Never hand-color a
  `Text`. Replace bespoke priority/status `CircleAvatar`s (super-tickets) with the
  badge system.

### 3.7 Anti-patterns to delete on sight
Flat undifferentiated lists · plain-`Text` section headers · debug-dump detail
pages · duplicate empty-CTA + FAB · orphaned filter bars · one-line tiles that wrap
into mush · forms that are one ungrouped scroll · 3× copy-pasted sections · sheets
that clip behind the keyboard · charts whose only labels are hover tooltips ·
`.take(N)`/`limit` with no "load more" affordance · layout jitter from conditional
fields.

---

## 4. Screen catalog

> **Order = leverage.** Do **§4.1 (shells/nav)** and **§4.2 (home dashboards)**
> first — they set the frame every other screen sits in and define the navigation
> spine. Then work down. Each entry: **Files** (presentation + the data/model to
> read + backing table) · **Renders** · **Problems** · **Revamp target**.
>
> "Screen" = the page **and all its nested components/sections.** Revamp the whole
> unit, including private `_Widget`s and embedded sections.

---

### 4.1 App shells & navigation — *do first; sets the frame*

The single biggest "production vs project" tell here is **inconsistency between
shells**: owner & super-admin have AppBars, coach & parent don't; profile/logout
access is scattered (AppBar person-icon here, Settings tab there, logout icon
elsewhere). Fix the **shell contract** once, apply to all five.

#### `features/home/owner_home_shell.dart`
- **Files:** [owner_home_shell.dart](apps/mobile/lib/features/home/owner_home_shell.dart) · profile from [profile_providers.dart](apps/mobile/lib/features/auth/data/profile_providers.dart) · `verification_banner` (shared widget).
- **Renders:** 5-tab `NavigationBar` (Home/Students/Coaches/Batches/Settings) over an `IndexedStack`; AppBar title flips between `BrandWordmark` and tab name; person-icon → ProfilePage.
- **Problems:** AppBar title jank on tab switch; profile is on AppBar but **logout is buried in Settings**; verification banner has no dismiss; no consistent place for account access.
- **Revamp target:** Define the canonical shell: stable AppBar per tab (wordmark only on Home, else the tab title — pick one rule and keep it), a single **account entry point** (avatar/person → a profile+logout menu or sheet) present on *every* shell. Make `VerificationBanner` a compact, dismissible inline strip that doesn't shove the body down permanently.

#### `features/coach/presentation/coach_home_shell.dart`
- **Files:** [coach_home_shell.dart](apps/mobile/lib/features/coach/presentation/coach_home_shell.dart) · `unreadNotificationCountProvider`.
- **Renders:** 5-tab nav (Home/My Batches/Announcements/Messages/Alerts), **no AppBar**, badge on Alerts only.
- **Problems:** Bare — no title, no account access; only Alerts shows a badge while Messages/Notices don't.
- **Revamp target:** Adopt the canonical shell contract (§4.1 owner): give it the same AppBar + account entry point. Add unread affordances to Messages/Notices tabs (or justify why only Alerts). Keep tab set/role gating identical.

#### `features/parent/presentation/parent_home_shell.dart` · `features/student/presentation/student_home_shell.dart`
- **Files:** [parent_home_shell.dart](apps/mobile/lib/features/parent/presentation/parent_home_shell.dart) · [student_home_shell.dart](apps/mobile/lib/features/student/presentation/student_home_shell.dart) (subclass).
- **Renders:** 4-tab nav (Home/Notices/Messages/Alerts), no AppBar; student shell inherits parent.
- **Problems:** Same bare-shell issue; no account access; parents have nowhere to reach settings/password.
- **Revamp target:** Same canonical shell contract. Keep the student=parent inheritance (DRY is correct) but ensure the account menu exposes profile + sign-out for these roles too.

#### `features/super_admin/presentation/super_admin_home_shell.dart`
- **Files:** [super_admin_home_shell.dart](apps/mobile/lib/features/super_admin/presentation/super_admin_home_shell.dart).
- **Renders:** 4-tab nav (Health/Academies/Plans/Tickets); AppBar = `BrandWordmark` + a hand-rolled "Admin" row badge; logout icon.
- **Problems:** Bespoke badge layout; no profile access; dense.
- **Revamp target:** Replace the hand-rolled badge with `AppBadge`. Apply the canonical account entry point. Keep tabs.

#### `features/settings/settings_tab.dart`
- **Files:** [settings_tab.dart](apps/mobile/lib/features/settings/settings_tab.dart) · profile/role from profile_providers.dart.
- **Renders:** Flat divider-separated list of 8 role-gated `AppListTile`s ending in Sign out.
- **Problems:** No grouping; Sign out lost at the bottom; role-hidden items are silent.
- **Revamp target:** Group under `AppSectionHeader`s (e.g. **Academy** · **Team & access** · **Billing** · **Account**). Put Sign out in its own **Account** group with clear affordance. Keep every role gate exactly as is.

#### `features/dashboards/role_dashboard.dart`
- **Files:** [role_dashboard.dart](apps/mobile/lib/features/dashboards/role_dashboard.dart).
- **Renders:** Router widget — `if/else` cascade on `profile.role`/flags → the right shell; `_RoleStub` fallback.
- **Problems:** Logic-only; loading shows nothing friendly; stub is a dead-end.
- **Revamp target:** **Behavior-preserving only.** Give the loading state an `AppLoading`, give `_RoleStub`/error an `AppEmptyState`/`AppErrorView` with a sign-out escape. Do **not** restructure the routing logic.

#### `features/auth/presentation/auth_scaffold.dart`
- **Files:** [auth_scaffold.dart](apps/mobile/lib/features/auth/presentation/auth_scaffold.dart).
- **Renders:** Centered max-440 column wrapper for all auth pages; `Positioned` back button; `BrandMark`; `AuthMessage` banner.
- **Problems:** Back button is a tiny easy-to-miss corner icon; tight on tablets.
- **Revamp target:** Promote the back affordance to a proper leading nav. Let the column breathe a bit on wider screens. This is the shared frame for §4.3 — get it right once.

---

### 4.2 Home dashboards / landing tabs — *do early*

#### `features/home/home_tab.dart`
- **Files:** [home_tab.dart](apps/mobile/lib/features/home/home_tab.dart) · `myAcademyProvider`, `centersProvider`, `studentsProvider`, `coachesProvider`, `batchesProvider`, `todaysBatchesProvider`.
- **Renders:** Greeting card → academy card → **`_ActionsCard` = 11 divider-separated tiles** → two stat rows (centers/students, coaches/batches).
- **Problems:** The 11-item flat menu is the headline offender — no grouping, all equal priority; stats split from the academy card.
- **Revamp target:** This is the §3.4 reference fix. Greeting/hero → 2-up `AppStatTile` KPI grid (students/coaches/batches/centers together) → **grouped** action sections under `AppSectionHeader`s (Daily ops · Money · Growth · Comms), primary above tertiary. Keep every destination and its gate.

#### `features/home/center_admin_home_tab.dart`
- **Files:** [center_admin_home_tab.dart](apps/mobile/lib/features/home/center_admin_home_tab.dart) · same providers, RLS-narrowed.
- **Problems:** Near-clone of home_tab with items removed, not a designed layout; center name derivation fragile.
- **Revamp target:** Apply the same §3.4 anatomy at center scope; surface **which center** as a clear sub-header, not buried in greeting text.

#### `features/coach/presentation/coach_home_tab.dart`
- **Files:** [coach_home_tab.dart](apps/mobile/lib/features/coach/presentation/coach_home_tab.dart) · `myCoachRecordProvider`, `myCoachStatsProvider`, `myTodaysBatchesProvider`, `coachAttendanceTrendProvider` (coach_home_providers.dart).
- **Renders:** Greeting → 3 stat tiles → today's-sessions tile → attendance bar chart → conditional Today list.
- **Problems:** Stats vanish when no coach record (blank flow); chart legend/axes confusing; empty "Today" is vague.
- **Revamp target:** §3.4 anatomy. Always-present KPI row (graceful "not linked yet" state that doesn't collapse the layout), a labeled attendance-trend section with readable axes, and an explicit `AppEmptyState` for "no sessions today".

#### `features/parent/presentation/parent_dashboard_tab.dart`
- **Files:** [parent_dashboard_tab.dart](apps/mobile/lib/features/parent/presentation/parent_dashboard_tab.dart) · `myLinkedStudentsProvider`, `studentAttendanceProvider`, `studentAttendanceWeeklyProvider`, `studentPerformanceProvider`, `mediaForStudentProvider`, `studentOutstandingDuesProvider`, `studentUpcomingSessionsProvider`, `myLinkedStudentBatchesProvider` (parent_providers.dart).
- **Renders:** Per-student dashboard: `SegmentedButton` switcher → header → upcoming sessions → batches → attendance heatmap+bars → performance line → media gallery → outstanding dues w/ Pay → events. **8 stacked sections.**
- **Problems:** Scroll fatigue; 60-day heatmap dense; chart points unlabeled; inline Razorpay Pay with no confirmation; switcher appears/disappears with student count.
- **Revamp target:** Tame the density — make the **student switcher persistent and prominent** (top, even for one child, as a stable header), then prioritize sections (next session + dues first), and consider collapsing the heavier visualizations behind clear section headers. Add a confirmation step before Pay. Keep every provider and the RazorpayCheckout wiring.

---

### 4.3 Auth & onboarding

#### `features/auth/presentation/splash_page.dart`
- **Files:** [splash_page.dart](apps/mobile/lib/features/auth/presentation/splash_page.dart) · `sessionProvider`.
- **Problems:** Bare spinner; no feedback on slow sessions.
- **Revamp target:** Brand lockup + `AppLoading` with a status line; keep routing logic.

#### `features/auth/presentation/login_page.dart` · `signup_page.dart` · `forgot_password_page.dart` · `set_new_password_page.dart`
- **Files:** the four pages · all wrap [auth_scaffold.dart](apps/mobile/lib/features/auth/presentation/auth_scaffold.dart); profile bootstrap in profile_providers.dart.
- **Problems:** Login: "Forgot password?" easy to miss, password has no validator. Signup: academy-name-first ordering, first/last `Row` collapses on narrow, no inline validation. Forgot: sparse single field, weak back affordance. Set-new-password: new+confirm share one obscure toggle (anti-pattern), no strength cue.
- **Revamp target:** Apply §3.3 form anatomy inside the auth frame: clear field order (user details before academy name on signup), graceful stacking of paired fields, inline validation, independent obscure toggles on the reset page, a prominent primary action and a clearly-secondary alt link. Don't touch the auth calls.

#### `features/auth/presentation/profile_page.dart`
- **Files:** [profile_page.dart](apps/mobile/lib/features/auth/presentation/profile_page.dart) · `currentProfileProvider`; avatar via `storageServiceProvider`.
- **Renders:** Big centered avatar → editable name/phone → read-only email/role → Save.
- **Problems:** Avatar eats vertical space; editable and read-only fields visually mixed; no unsaved-changes cue.
- **Revamp target:** Compact header (avatar + name inline), then an editable **Your details** section and a visually distinct read-only **Account** section (§3.3). Keep the upload + update + invalidate flow.

#### `features/dashboards/setup_academy_page.dart`
- **Files:** [setup_academy_page.dart](apps/mobile/lib/features/dashboards/setup_academy_page.dart) · `bootstrapOwnerAcademy` in profile_providers.dart.
- **Problems:** Error styling inconsistent with the auth `AuthMessage`; narrow on tablet.
- **Revamp target:** Reuse the `AuthMessage`/`AppErrorView` pattern for errors; align with the auth frame; explain the one-step onboarding briefly.

---

### 4.4 People & org management

> **Cross-cutting for this group:** make the three parallel "people lists"
> (students, coaches, team) share **one tile + filter pattern** (search + status +
> optional sport, result count, consistent subtitle). Today students has rich
> filters, coaches has none, team is flat — that inconsistency is the main tell.
> `StudentDocumentsSection`/`CoachDocumentsSection` are near-duplicates — revamp
> them to the **same** section layout.

#### `features/students/presentation/students_tab.dart`
- **Files:** [students_tab.dart](apps/mobile/lib/features/students/presentation/students_tab.dart) · [student.dart](apps/mobile/lib/features/students/data/student.dart) + [student_providers.dart](apps/mobile/lib/features/students/data/student_providers.dart); table `…_students` migration.
- **Renders:** Search row + filter/import icons + `SportFilterChipBar` + list of avatar tiles (name / sport·skill·parent / status badge).
- **Problems:** Cramped search+icon row; sport chips orphaned from filters; no result count; dense wrapping subtitle.
- **Revamp target:** §3.1 list anatomy with a **unified filter bar** (search + status + sport in one coherent block), a result count, and a 2-fact subtitle. This becomes the template for coaches & team.

#### `features/students/presentation/student_form_page.dart`
- **Files:** [student_form_page.dart](apps/mobile/lib/features/students/presentation/student_form_page.dart) · student.dart + student_providers.dart, center_providers.dart, sport_providers.dart; embeds the four sections below.
- **Renders:** Avatar → Student/Parent/Training/Other sections → (edit only) attendance+performance callouts, fees, discounts, documents, logins → Save.
- **Problems:** Flat IA; required vs optional unclear; create/edit structurally different; logins section crams two concepts; info callouts mixed into the form.
- **Revamp target:** §3.3 — tighten section grouping (contact together, training together), make required markers consistent, present edit-only sections clearly below a divider with labels, and split the **Logins & access** card into two labeled rows (parent link / student login).

#### `features/students/presentation/student_documents_section.dart` · `features/coaches/presentation/coach_documents_section.dart`
- **Files:** the two sections · [student_document.dart](apps/mobile/lib/features/students/data/student_document.dart)/[coach_document.dart](apps/mobile/lib/features/coaches/data/coach_document.dart) + their `*_providers.dart`; `kStudent/CoachDocumentTypes`.
- **Problems:** Type-picker is an unlabeled list; weak upload affordance; no upload date metadata; generic delete confirm.
- **Revamp target:** **One shared section layout** for both: `AppSectionHeader` + prominent upload action, doc tiles showing type + size + **date**, a type-picker sheet with short descriptions, and a delete confirm that names the file.

#### `features/students/presentation/student_bulk_import_page.dart` · `features/coaches/presentation/coach_bulk_import_page.dart`
- **Files:** the two pages · student/coach models + providers; `academyCenterSportsProvider`.
- **Problems:** Schema explained as plain text; `DataTable` horizontal-scroll preview clunky; only first error surfaced; no progress; pipe-separator notation cryptic (coaches).
- **Revamp target:** A clear **3-step layout** (1 download/understand template → 2 pick & preview → 3 import & results), a readable preview (cards or a tidy table with invalid rows flagged inline), per-row error reporting, and an import progress indicator. Keep the CSV parsing + insert logic.

#### `features/coaches/presentation/coaches_tab.dart`
- **Files:** [coaches_tab.dart](apps/mobile/lib/features/coaches/presentation/coaches_tab.dart) · [coach.dart](apps/mobile/lib/features/coaches/data/coach.dart) + coach_providers.dart.
- **Problems:** Import is a top-right text button (not FAB); **no search/filter**; no status badge; subtitle crams 3 facts.
- **Revamp target:** Match the students_tab template (§3.1): FAB for create, unified filter/search, status badge, 2-fact subtitle.

#### `features/coaches/presentation/coach_form_page.dart`
- **Files:** [coach_form_page.dart](apps/mobile/lib/features/coaches/presentation/coach_form_page.dart) · coach.dart + coach_providers.dart, `coachSportsProvider`, center/sport providers.
- **Problems:** Expertise section conflates sports/specialization/experience; comma-text fields; sports loaded via fragile microtask with no loading cue; ambiguous login card state; required/optional unclear.
- **Revamp target:** §3.3 — regroup Expertise (sports multi-select as its own labeled block, separate from free-text specialization), give the async sports load a loading state, clarify the login/invite card's states (none/pending/active), consistent required markers.

#### `features/centers/presentation/centers_tab.dart` · `centers_page.dart` · `center_form_page.dart`
- **Files:** the three · [center.dart](apps/mobile/lib/features/centers/data/center.dart) + center_providers.dart.
- **Problems:** "Inactive" only in subtitle (no badge); **duplicate empty-CTA + FAB**; tile shows no context (coach/batch counts); `centers_page` double-header when pushed from Settings; form omits model fields (state, pincode, email, facilities, adminId); deactivate button floats far from fields.
- **Revamp target:** §3.1 list (status `AppBadge`, single create path, optional count context). Resolve the double-AppBar wrapper. Form: §3.3 grouping, expose the fields the model supports, and place activate/deactivate as a clearly-separated **danger/lifecycle** action.

#### `features/users/presentation/team_page.dart` · `invite_user_sheet.dart`
- **Files:** [team_page.dart](apps/mobile/lib/features/users/presentation/team_page.dart) · [invite_user_sheet.dart](apps/mobile/lib/features/users/presentation/invite_user_sheet.dart) · [invite_repo.dart](apps/mobile/lib/features/users/data/invite_repo.dart) (`teamMembersProvider`).
- **Problems:** Flat list of all roles (no grouping); no search; long email subtitle wraps; subtle inactive badge; sheet's preset mode hides which role is assigned.
- **Revamp target:** **Group members by role** under `AppSectionHeader`s (Owners/Admins/Coaches/…), add search, status `AppBadge`, and a clean 2-line tile. Sheet (§3.5): clear title, make the assigned role obvious even in preset mode, keep center-admin conditional center field (and clear it when role changes).

#### `features/academy/presentation/academy_settings_page.dart`
- **Files:** [academy_settings_page.dart](apps/mobile/lib/features/academy/presentation/academy_settings_page.dart) · [academy.dart](apps/mobile/lib/features/academy/data/academy.dart) + academy_providers.dart.
- **Renders:** Logo → Profile / Operating hours / Holidays / Invoicing in one scroll.
- **Problems:** Four unrelated concerns in one undifferentiated form; hours use bespoke `InkWell` instead of fields; holidays-add workflow awkward; no end-after-start validation; invoice prefix unexplained.
- **Revamp target:** Strong §3.3 sectioning (the four areas as clearly separated, card-grouped sections — or tabs if it stays one page). Use `AppDateField`/time fields consistently for hours; make holiday add/remove a tidy chip+add block; show an example invoice-number from the prefix.

#### `features/sports/presentation/sports_settings_page.dart` · `sport_picker.dart`
- **Files:** [sports_settings_page.dart](apps/mobile/lib/features/sports/presentation/sports_settings_page.dart) · [sport_picker.dart](apps/mobile/lib/features/sports/presentation/sport_picker.dart) · [sport.dart](apps/mobile/lib/features/sports/data/sport.dart) + sport_providers.dart (`centerSportsProvider`, `allSportsProvider`).
- **Problems:** Center dropdown visually disconnected from the list it drives; add-sheet has no search over the catalog; rename/remove hidden in popup; inconsistent empty fallbacks across the three picker widgets.
- **Revamp target:** Make the **center selector clearly the scope control** for the list below (sticky header with "Sports at <center>"). Give the add-sport sheet a search field. Surface rename as a visible action. Normalize the three pickers' empty states to one pattern.

---

### 4.5 Training operations

#### `features/batches/presentation/batches_tab.dart`
- **Files:** [batches_tab.dart](apps/mobile/lib/features/batches/presentation/batches_tab.dart) · [batch.dart](apps/mobile/lib/features/batches/data/batch.dart) + batch_providers.dart; table `…_batches`.
- **Renders:** `SportFilterChipBar` + list of tiles (name / schedule·sport·skill / enrolled count).
- **Problems:** Filter feels disconnected; trailing enrolled-count column adds height; no active/archived status cue.
- **Revamp target:** §3.1 with unified filter, a compact `AppBadge` for capacity/status, and a tighter tile.

#### `features/batches/presentation/batch_form_page.dart` · `schedule_picker.dart`
- **Files:** [batch_form_page.dart](apps/mobile/lib/features/batches/presentation/batch_form_page.dart) · [schedule_picker.dart](apps/mobile/lib/features/batches/presentation/schedule_picker.dart) · batch.dart, centers/coaches/sport providers.
- **Problems:** Very tall form; sport+age cramped in a `Row`; center & coach dropdowns flicker separate progress bars; schedule picker bulky; skill-level required-ness unclear; single floating error.
- **Revamp target:** §3.3 grouping (Details · Schedule · Capacity). Stabilize async dropdowns (skeleton, no flicker). Tighten `SchedulePicker`: day chips that wrap tidily + two clearly-interactive time fields showing current values, with start<end validation.

#### `features/batches/presentation/batch_detail_page.dart` (+ fees/discounts sections — see §4.6)
- **Files:** [batch_detail_page.dart](apps/mobile/lib/features/batches/presentation/batch_detail_page.dart) · `batchEnrollmentsProvider`, studentsProvider, caps; embeds `BatchFeesSection`/`BatchDiscountsSection`.
- **Renders:** Metadata card → enroll header+button → fees → discounts → **three repeated `_EnrollmentSection`s** (Active/Waitlist/Withdrawn) → enroll/transfer sheets.
- **Problems:** Three copy-pasted enrollment sections; dense multi-line metadata; enroll button competes with title; action-row icons cause jitter; headerless transfer/enroll sheets.
- **Revamp target:** §3.2 detail anatomy — header card with scannable facts + status badges; **one** enrollment section component rendered per status group with a count sub-header; stable per-row action set; titled, scrollable enroll/transfer sheets (§3.5). Keep capacity logic and all gates.

#### `features/attendance/presentation/todays_sessions_page.dart`
- **Files:** [todays_sessions_page.dart](apps/mobile/lib/features/attendance/presentation/todays_sessions_page.dart) · `todaysBatchesProvider`, `attendanceForBatchProvider`; [attendance.dart](apps/mobile/lib/features/attendance/data/attendance.dart).
- **Problems:** "all marked" green dot reads as "present"; 0/0 ambiguous; no per-session context.
- **Revamp target:** §3.1 list with a clear **progress affordance** per session (e.g. "5/8 marked" + a determinate ring/badge), distinct empty state, and an unambiguous "no students" vs "not started" cue.

#### `features/attendance/presentation/attendance_marking_page.dart`
- **Files:** [attendance_marking_page.dart](apps/mobile/lib/features/attendance/presentation/attendance_marking_page.dart) · `batchEnrollmentsProvider`, `attendanceForBatchProvider`.
- **Renders:** Date header → rows of name + 4-icon `SegmentedButton` + conditional note field → Save footer; "Mark all present" in AppBar.
- **Problems:** Icon-only status buttons hard to read; note field pops in/out (jitter); date shown as `YYYY-MM-DD`; "mark all" far from the list; no completion indicator.
- **Revamp target:** A clean per-student attendance card: readable status selector, **reserved** (non-jittering) note area, a human date header, a visible "Mark all present" near the list, and a completion/progress cue at the footer. Keep the status/notes state maps and save flow.

#### `features/attendance/presentation/admin_attendance_overview.dart`
- **Files:** [admin_attendance_overview.dart](apps/mobile/lib/features/attendance/presentation/admin_attendance_overview.dart) · `_todaysAttendanceStreamProvider`, batches/students providers.
- **Problems:** 4 equal stat cells; activity capped at `.take(40)` silently; no timestamps on rows; hardcoded status colors; no filter.
- **Revamp target:** §3.4 KPI grid via `AppStatTile` (theme-aware status via `AppSemanticColors`), an activity list with **timestamps** and an explicit "showing latest 40 · load more" cue. Keep the realtime stream.

#### `features/performance/presentation/performance_form_page.dart`
- **Files:** [performance_form_page.dart](apps/mobile/lib/features/performance/presentation/performance_form_page.dart) · [performance.dart](apps/mobile/lib/features/performance/data/performance.dart) + performance_providers.dart, `sportSkillsProvider`.
- **Renders:** Sport picker → skill rows (name + 1–10 slider + score + remove) → Add skill → feedback → average → (post-save) evidence → Save/Done.
- **Problems:** Locks read-only after save (no edit); skill rows cramped via flex; slider label jitter; media only after save; lost text on failure.
- **Revamp target:** Restructure the skill row so name/slider/score don't crush on narrow screens; stabilize the score label; present the evidence/media section as a clear post-save section without making the rest feel disabled. (If "edit after save" is a real gap, flag it — that's behavior, not layout.)

#### `features/performance/presentation/performance_detail_page.dart`
- **Files:** [performance_detail_page.dart](apps/mobile/lib/features/performance/presentation/performance_detail_page.dart) · `skillsForAssessmentProvider`, `mediaForAssessmentProvider`.
- **Problems:** Minimal score callout (hidden if null); uneven skill-row heights; ugly long file paths; tiny open icon; no recorded-at line.
- **Revamp target:** §3.2 — a real **overall-score callout card**, consistent skill rows, a media list showing friendly filenames + type badge + a clear open affordance, and the assessment date in the body (not just the AppBar).

#### `features/performance/presentation/performance_history_page.dart`
- **Files:** [performance_history_page.dart](apps/mobile/lib/features/performance/presentation/performance_history_page.dart) · `assessmentsForStudentProvider`, `performanceTrendProvider`, caps.
- **Problems:** Weak score avatar; "—" ambiguous; date+feedback cram into one subtitle; **duplicate empty-CTA + FAB**; no filtering.
- **Revamp target:** §3.1 list with a clear **trend header card**, a prominent score chip per row, a 2-line tile (date, then feedback), and a single create path (FAB only).

#### `features/coach/presentation/coach_batches_tab.dart`
- **Files:** [coach_batches_tab.dart](apps/mobile/lib/features/coach/presentation/coach_batches_tab.dart) · `myBatchesProvider`.
- **Problems:** Static icon; subtitle wraps; chat button + chevron cause trailing jitter; no metadata.
- **Revamp target:** §3.1 tile with stable trailing area, optional enrolled count, tidy subtitle.

#### `features/coach/presentation/coach_student_page.dart`
- **Files:** [coach_student_page.dart](apps/mobile/lib/features/coach/presentation/coach_student_page.dart) · student model, `studentAttendanceProvider`, `mediaForStudentProvider`, caps.
- **Renders:** Profile card → attendance-60d card → performance link → media gallery card.
- **Problems:** Cards-within-cards for media; plain-text parent contact (not tappable); 96px thumbs; badges wrap; no media count; no empty explanation when upload gated.
- **Revamp target:** §3.2 — a clean profile header, an attendance summary with a small trend cue, tappable contact rows, and a media section with a count + larger thumbs (flatten the card-in-card). Keep upload gating + signed-URL flow.

---

### 4.6 Billing & subscription

> **Cross-cutting:** add **confirmation** before destructive money actions
> (deactivate fee/discount, refund, stop billing) — these silently affect future
> invoices today. The four embedded sections below should share one section layout
> with a consistent active/inactive badge.

#### `features/billing/presentation/billing_dashboard_page.dart`
- **Files:** [billing_dashboard_page.dart](apps/mobile/lib/features/billing/presentation/billing_dashboard_page.dart).
- **Renders:** Scrollable 5-tab bar (Invoices/Fees/Discounts/Payments/Reports) → TabBarView.
- **Problems:** 5 scrollable tabs mix transactional (invoices/payments) with config (fees/discounts) and reports.
- **Revamp target:** Reconsider grouping so transactional vs. configuration aren't peers competing for tab space (e.g. a Reports/overview landing + grouped sub-navigation). Keep all five destinations reachable.

#### `features/billing/presentation/invoice_list_page.dart`
- **Files:** [invoice_list_page.dart](apps/mobile/lib/features/billing/presentation/invoice_list_page.dart) · [invoice.dart](apps/mobile/lib/features/billing/data/invoice.dart) + [billing_providers.dart](apps/mobile/lib/features/billing/data/billing_providers.dart) (`invoicesProvider`, `invoiceFilterProvider`); tables `…_invoices`.
- **Problems:** Filter chips read like a tag cloud; no result count; tile lacks aged-balance cue.
- **Revamp target:** §3.1 unified filter bar + count; tile shows invoice#, student, due date, amount, and a status `AppBadge` with overdue emphasis.

#### `features/billing/presentation/invoice_detail_page.dart`
- **Files:** [invoice_detail_page.dart](apps/mobile/lib/features/billing/presentation/invoice_detail_page.dart) · invoice.dart, [payment.dart](apps/mobile/lib/features/billing/data/payment.dart), `invoiceLineItemsProvider`, `paymentsForInvoiceProvider`.
- **Renders:** Summary card → conditional outstanding-actions → plain-`Text` "Line items" → plain-`Text` "Payments".
- **Problems:** Total/Paid/Balance row wraps; CTAs only appear when balance>0; plain-text headers = debug-dump feel; clunky Razorpay copy-paste.
- **Revamp target:** §3.2 — a **balance-forward summary** with a clear primary "Record payment" action, `AppSectionHeader`s for Line items & Payments rendered as grouped lists, and `AppBadge` line-item kinds.

#### `features/billing/presentation/record_payment_page.dart` · `refund_form_page.dart`
- **Files:** the two · `recordManualPayment`, `requestRefund` (billing_providers.dart).
- **Problems:** No confirmation before recording; method-exclusions/INR not explained; refund has no partial-refund clarity; reason not enforced; no receipt cue on success.
- **Revamp target:** §3.3 form: a clear "you're paying ₹X against invoice Y" header, an INR-marked amount, a confirmation step, and a success summary. Refund: explain manual vs Razorpay path, support partial amount clearly, enforce reason.

#### `features/billing/presentation/payments_list_page.dart`
- **Files:** [payments_list_page.dart](apps/mobile/lib/features/billing/presentation/payments_list_page.dart) · `_allPaymentsProvider` (limit 200), studentsProvider.
- **Problems:** Silent 200 cap; no date grouping; redundant method icon+label; tiles don't navigate; no filters.
- **Revamp target:** §3.1 with date-grouped sections, an explicit "load more"/cap cue, tappable rows → invoice, and a method filter.

#### `features/billing/presentation/fee_structures_page.dart` · `fee_structure_form_page.dart`
- **Files:** the two · [fee_structure.dart](apps/mobile/lib/features/billing/data/fee_structure.dart) + billing_providers.dart.
- **Problems:** List buries late-fee/grace detail; no sort/filter; inactive only via badge; form's side-by-side fields wrap; policy options unexplained; grace-days free text; no invoice preview.
- **Revamp target:** §3.1 list with status badge + key terms in subtitle. §3.3 form grouped (Fee · Late fee · Status), gracefully-stacking paired fields, brief inline help on policy options, and an example of how the fee renders on an invoice.

#### `features/billing/presentation/discount_structures_page.dart` · `discount_structure_form_page.dart`
- **Files:** the two · [discount.dart](apps/mobile/lib/features/billing/data/discount.dart) + [discount_providers.dart](apps/mobile/lib/features/billing/data/discount_providers.dart).
- **Problems:** List can't show assignment count; mixed %/flat is visual noise; type-driven form label changes are confusing; stacking behavior unexplained.
- **Revamp target:** §3.1 list with a clean value badge (% vs ₹). §3.3 form where the type selector clearly reshapes the value field, with help on how the discount stacks.

#### `features/billing/presentation/financial_reports_page.dart`
- **Files:** [financial_reports_page.dart](apps/mobile/lib/features/billing/presentation/financial_reports_page.dart) · derived from `invoicesProvider`.
- **Problems:** Fixed last-30-days, no date range; "by status" rows don't pivot to a filtered list; missing collection-rate/aging KPIs.
- **Revamp target:** §3.4 KPI layout; make "by status" rows tap through to the filtered invoice list. (Date-range/extra KPIs that need new queries → flag, don't invent.)

#### `features/billing/presentation/batch_fees_section.dart` · `batch_discounts_section.dart` · `student_fees_section.dart` · `student_discounts_section.dart`
- **Files:** the four · billing_providers.dart / discount_providers.dart (`assignmentsForBatch/StudentProvider`, etc.), caps `manageFinance`.
- **Problems:** Near-duplicate code with inconsistent active/inactive treatment; deactivate has no confirmation; assignment sheets don't explain invoice-generation mapping or stacking; embedded with no breadcrumb.
- **Revamp target:** **One shared assignment-section layout** for all four: `AppSectionHeader` + gated assign action, tiles with a consistent active/inactive `AppBadge`, a titled assign **sheet** (§3.5) with a one-line "this generates invoices on …" explainer, and a confirm on deactivate. Keep `canManage`/`manageFinance` gates.

#### `features/subscription/presentation/subscription_page.dart`
- **Files:** [subscription_page.dart](apps/mobile/lib/features/subscription/presentation/subscription_page.dart) · [subscription_providers.dart](apps/mobile/lib/features/subscription/data/subscription_providers.dart) (`mySubscriptionProvider`, `availablePlansProvider`, `mySaasInvoicesProvider`).
- **Renders:** Current-plan card → plan cards (Request change) → past SaaS invoices.
- **Problems:** No renewal/trial urgency cue; plan cards hard to compare; "Request change" is a dead-end snackbar; invoices have no actions.
- **Revamp target:** §3.2 — current-plan card with a clear status/renewal `AppBadge`, comparable plan cards (aligned price + limits), and a past-invoices list matching the billing invoice tile. (Plan-change backend is out of scope — keep the existing request behavior but make it read as intentional.)

---

### 4.7 Engagement

#### `features/leads/presentation/leads_kanban_page.dart`
- **Files:** [leads_kanban_page.dart](apps/mobile/lib/features/leads/presentation/leads_kanban_page.dart) · [lead.dart](apps/mobile/lib/features/leads/data/lead.dart) + [lead_providers.dart](apps/mobile/lib/features/leads/data/lead_providers.dart); table `…_leads`.
- **Renders:** Horizontal 6-column kanban (280px cols), cards with name/sport/contact/followup.
- **Problems:** Fixed column width (not responsive); narrow cramped cards; low-contrast "—" empties; all leads loaded at once.
- **Revamp target:** Keep the kanban metaphor but make columns breathe and cards scannable (name + status + next-followup with overdue emphasis); give empty columns a proper mini empty state; ensure the board is usable on a phone (consider snap-scroll per column). Flag pagination if lists get large.

#### `features/leads/presentation/lead_detail_page.dart`
- **Files:** [lead_detail_page.dart](apps/mobile/lib/features/leads/presentation/lead_detail_page.dart) · `leadByIdProvider`, `leadActivitiesProvider`.
- **Renders:** Header card → status actions (ChoiceChips + Convert + Schedule trial) → contact card → activity timeline + add-note row.
- **Problems:** Dense status+actions block; two-picker trial scheduling; header/contact redundancy; add-note row gets covered by keyboard; flat activity list.
- **Revamp target:** §3.2 — header with status badge, a clear **status/actions** zone (status control separate from primary buttons), a real **activity timeline** (grouped, with relative+absolute time), and a note composer that stays above the keyboard.

#### `features/leads/presentation/lead_form_page.dart` · `lead_convert_sheet.dart`
- **Files:** the two · lead.dart + lead_providers.dart (`create`, `convert` via edge fn).
- **Problems:** Required fields (firstName, phone-OR-email) split across sections, validated only on submit; convert sheet's "No initial batch" reads like a real option; no success confirmation.
- **Revamp target:** §3.3 form grouping + inline cross-field validation. Convert sheet (§3.5): titled, with a clear placeholder for "no batch", a loading state for the batch list, and success feedback.

#### `features/announcements/presentation/announcements_page.dart`
- **Files:** [announcements_page.dart](apps/mobile/lib/features/announcements/presentation/announcements_page.dart) · [announcement.dart](apps/mobile/lib/features/announcements/data/announcement.dart) + announcement_providers.dart (`announcementsListProvider`, `announcementFeedProvider`).
- **Renders:** Admin list (drafts/sent) **or** recipient feed (unread dot + tap→dialog), role-switched.
- **Problems:** Two layouts feel like two apps; feed dialog marks read late; weak unread dot; 2-line preview; redundant refresh.
- **Revamp target:** Unify the two views onto a shared list anatomy (§3.1) with a clear unread affordance and `AppBadge` for Draft/Sent; open feed items on a real detail surface (not a bare dialog) and mark read predictably.

#### `features/announcements/presentation/announcement_composer_page.dart`
- **Files:** [announcement_composer_page.dart](apps/mobile/lib/features/announcements/presentation/announcement_composer_page.dart) · announcement_providers.dart (`draft` + `sendNow`, edge fn).
- **Problems:** Three scattered audience selectors (roles/batches/centers) with unclear AND/OR; lazy pickers with no loading state; channel toggles unguided; hidden draft→send step.
- **Revamp target:** §3.3 — a clear **Audience** section that communicates the targeting model (and "empty = everyone"), pickers with loading states, a labeled **Channels** group, and an obvious send affordance.

#### `features/chat/presentation/threads_page.dart` · `thread_detail_page.dart`
- **Files:** the two · [chat.dart](apps/mobile/lib/features/chat/data/chat.dart), [attachment.dart](apps/mobile/lib/features/chat/data/attachment.dart) + chat_providers.dart (`myThreadsProvider`, `threadMessagesProvider`).
- **Problems (list):** "—" preview default; cryptic relative time; async name flicker; no unread badge; no search. **(detail):** auto-scroll can miss new messages; pending-attachment chips eat composer space; no message timestamps; no edit/delete; attachment picker is a plain sheet.
- **Revamp target:** Threads → §3.1 with a proper "No messages yet" preview, stable name resolution, and an unread affordance. Detail → a solid chat layout: reliable scroll-to-latest, a composer whose attachment tray doesn't crowd the input, and visible message timestamps (grouped by day). Keep realtime + signed-URL attachment flow.

#### `features/chat/presentation/batch_chat_button.dart` · `message_parent_button.dart`
- **Files:** the two · chat_providers.dart (`ensureBatchThread`, `ensureDirectThread`), `_studentParentsProvider`.
- **Problems:** No/weak busy feedback; parent-button always present even with no parents (taps do nothing); no loading state for parent lookup.
- **Revamp target:** Clear busy/disabled visuals; hide or clearly disable the message-parent button when there are no linked parents; give the parent-picker sheet a title and loading state.

#### `features/notifications/presentation/notification_center_page.dart`
- **Files:** [notification_center_page.dart](apps/mobile/lib/features/notifications/presentation/notification_center_page.dart) · [notification.dart](apps/mobile/lib/features/notifications/data/notification.dart) + notification_providers.dart (`notificationsStreamProvider`).
- **Problems:** Unread = bold only (no dot/badge); flat list, no date grouping; compact time; mark-all-read has no confirm; possible stale deep links.
- **Revamp target:** §3.1 — clear unread affordance (dot/`AppBadge`), **group by date** (Today/Earlier), category icon + relative+absolute time, and a confirm on mark-all-read. Keep markRead + deepLink nav.

#### `features/notifications/presentation/notification_preferences_page.dart`
- **Files:** [notification_preferences_page.dart](apps/mobile/lib/features/notifications/presentation/notification_preferences_page.dart) · notification_providers.dart (`notificationPreferencesProvider`, `setPreference`).
- **Problems:** 8×3 = 24 toggles in a tall list; repeated headers; no master toggle; channels unexplained.
- **Revamp target:** A compact **category × channel matrix** (one row per category, three channel switches with a header row of channel labels) instead of 24 stacked tiles; optional per-channel "all on/off". Keep the upsert-per-toggle behavior.

#### `features/events/presentation/events_page.dart`
- **Files:** [events_page.dart](apps/mobile/lib/features/events/presentation/events_page.dart) · [event.dart](apps/mobile/lib/features/events/data/event.dart) + [event_providers.dart](apps/mobile/lib/features/events/data/event_providers.dart); table `…_events`.
- **Problems:** Two orphaned filter bars (status + sport); local-only filter state; lightweight cards; variable card height from multiline location; no sort.
- **Revamp target:** §3.1 unified filter bar (status + sport together), consistent event cards (kind icon + title + date/location + status `AppBadge`), stable card height.

#### `features/events/presentation/event_detail_page.dart` · `event_form_page.dart` · `event_register_sheet.dart` · `event_results_page.dart`
- **Files:** the four · event.dart + event_providers.dart (`eventByIdProvider`, `eventRegistrationsProvider`, `eventResultsProvider`, `register`, `recordResult`, cert edge fn), caps.
- **Problems:** Detail: status-transition buttons wrap awkwardly, registrations section doesn't scroll independently, hidden popup actions, no fee-paid status. Form: four separate date/time pickers, publish toggle buried, no start<end validation. Register sheet: no student search, "collect fee separately" workaround, silent disabled button. Results: three cramped inputs per row, save-before-generate coupling.
- **Revamp target:** Detail → §3.2 with status transitions as a clear control (not a button soup) and a registrations section with consistent rows + discoverable actions. Form → §3.3 grouped (Details · Schedule · Location & capacity · Description · Publish), a tidier date/time block, start<end validation, and a visible publish choice. Register sheet (§3.5) → titled, searchable student picker, explained fee note. Results → a readable per-student result card instead of three squeezed fields; clarify the save→generate flow.

---

### 4.8 Growth, analytics & inventory

#### `features/inventory/presentation/inventory_page.dart`
- **Files:** [inventory_page.dart](apps/mobile/lib/features/inventory/presentation/inventory_page.dart) · [inventory.dart](apps/mobile/lib/features/inventory/data/inventory.dart) + [inventory_providers.dart](apps/mobile/lib/features/inventory/data/inventory_providers.dart); table `…_inventory`.
- **Renders:** 3 tabs (All / Low stock / Vendors), context FAB, item tiles with on-hand + low-stock badge.
- **Problems:** FAB label doesn't reflect tab context; no pagination; low-stock badge crowds trailing; SKU-conditional subtitle varies row height.
- **Revamp target:** §3.1 tiles with stable subtitle + low-stock `AppBadge`; make the FAB's action match the active tab; flag pagination if inventories get large.

#### `features/inventory/presentation/inventory_item_page.dart` · `inventory_item_form_page.dart` · `movement_sheet.dart`
- **Files:** the three · inventory.dart + inventory_providers.dart (`itemMovementsProvider`, `recordMovement`, `upsertItem`), students/coaches/vendors/categories providers.
- **Problems:** Stock card height varies; movement list mixes tile types; uncapped history. Form: flat sections, conditional `_StockCard` blocks. Movement sheet: 4-button segmented wraps, qty-label changes but input doesn't, conditional recipient dropdowns cause reflow, no qty>0 inline validation.
- **Revamp target:** Detail → §3.2 stock-summary card with stable layout + a movements section (consistent tiles, capped + load-more). Form → §3.3 grouping. Movement sheet (§3.5) → titled, **reserved space** for recipient dropdowns (no reflow), inline qty validation, clear kind selector.

#### `features/inventory/presentation/vendors_page.dart`
- **Files:** [vendors_page.dart](apps/mobile/lib/features/inventory/presentation/vendors_page.dart) · inventory_providers.dart (`vendorsProvider`, `upsertVendor`).
- **Problems:** Edit sheet not scrollable (clips behind keyboard); unlabeled `name·phone·email` subtitle; active/inactive not shown.
- **Revamp target:** §3.1 list (show active status), §3.5 scrollable titled edit sheet.

#### `features/analytics/presentation/kpi_dashboard_page.dart`
- **Files:** [kpi_dashboard_page.dart](apps/mobile/lib/features/analytics/presentation/kpi_dashboard_page.dart) · [analytics_providers.dart](apps/mobile/lib/features/analytics/data/analytics_providers.dart) + [sport_breakdown.dart](apps/mobile/lib/features/analytics/data/sport_breakdown.dart) (`collectionSummaryProvider`, `revenueByMonthProvider`, `enrollmentByMonthProvider`, `batchUtilizationProvider`, `sportBreakdownProvider`, `leadFunnelProvider`).
- **Renders:** Role-aware sections: collection 2×2 stats, revenue bar, enrollment line, sport breakdown table, batch utilization, lead funnel.
- **Problems:** Fixed-height charts; stat tiles can overflow; hand-built breakdown table overflows on long sport names; funnel is a naive badge wrap; top-10 utilization with no "see all"; no "last updated".
- **Revamp target:** §3.4 — readable KPI grid, labeled chart sections with a "last updated" cue, a breakdown laid out so long names don't overflow, and a funnel that reads as a funnel. Keep all providers; flag anything needing a new query.

#### `features/reports/presentation/report_builder_page.dart`
- **Files:** [report_builder_page.dart](apps/mobile/lib/features/reports/presentation/report_builder_page.dart) · [report_builder.dart](apps/mobile/lib/features/reports/data/report_builder.dart) (`ReportEntity`, `ReportSpec`, `reportRunnerProvider`).
- **Problems:** Bare dropdowns, no hierarchy; cramped filter-editor rows; column chips show no selection summary; group-by/order-by semantics unclear; legacy `DataTable` hard to read on mobile; no type-aware filter inputs.
- **Revamp target:** A clear **builder layout**: Entity → Columns (with "5 of 30 selected" summary) → Filters (readable rows that stack on narrow screens) → Group/Order (with a one-line semantics hint) → Run → results. Make results readable on a phone (consider cards over a wide DataTable). Type-aware filter inputs are nice-to-have — flag if it needs new logic.

#### `features/audit/presentation/audit_log_page.dart`
- **Files:** [audit_log_page.dart](apps/mobile/lib/features/audit/presentation/audit_log_page.dart) · [audit_log.dart](apps/mobile/lib/features/audit/data/audit_log.dart) + [audit_log_providers.dart](apps/mobile/lib/features/audit/data/audit_log_providers.dart) (limit 50).
- **Problems:** `ExpansionTile`s make a long scroll; summary line is undifferentiated text; truncated changed-fields with no count; tiny diff text; no filter; silent 50 cap.
- **Revamp target:** §3.1/§3.2 hybrid — scannable rows (actor · action · entity as distinct elements + `AppBadge` for action kind), expand to a clean diff view, an explicit "latest 50 · load more" cue. Add entity/action filtering if cheap.

#### `features/support/presentation/support_page.dart`
- **Files:** [support_page.dart](apps/mobile/lib/features/support/presentation/support_page.dart) · [support_providers.dart](apps/mobile/lib/features/support/data/support_providers.dart) (`myAcademyTicketsProvider`, `createTicket`, `postReply`).
- **Problems:** New-ticket sheet doesn't scroll; cramped category/priority dropdowns; no unread/priority cue in list; flat thread (original vs first reply unclear); no avatars/timestamps.
- **Revamp target:** §3.1 ticket list (status + priority `AppBadge`), §3.5 scrollable titled new-ticket sheet, and a thread layout that clearly separates the original ticket from replies with timestamps.

---

### 4.9 Super-admin (platform)

#### `features/super_admin/presentation/global_health_page.dart`
- **Files:** [global_health_page.dart](apps/mobile/lib/features/super_admin/presentation/global_health_page.dart) · [super_admin_providers.dart](apps/mobile/lib/features/super_admin/data/super_admin_providers.dart) (`globalKpiProvider`, `allAcademiesProvider`).
- **Problems:** Revenue card lacks breakdown; 2-col grid of 5 tiles aligns oddly; no deltas; status counts don't drill down; placeholder system-health row.
- **Revamp target:** §3.4 KPI layout that handles the odd tile count cleanly; make status counts tap through to a filtered academies view; keep or clearly mark the placeholder as "coming in v1.1".

#### `features/super_admin/presentation/academies_page.dart`
- **Files:** [academies_page.dart](apps/mobile/lib/features/super_admin/presentation/academies_page.dart) · super_admin_providers.dart (`allAcademiesProvider`, `setAcademyActive`).
- **Problems:** Trailing `Switch` toggles active with **no confirmation** (can disable a whole academy by mistake); status as plain text; bare search; no pagination.
- **Revamp target:** §3.1 list with a status `AppBadge`, a styled search field, and a **confirmation** before toggling is_active. Flag pagination for scale.

#### `features/super_admin/presentation/plans_page.dart`
- **Files:** [plans_page.dart](apps/mobile/lib/features/super_admin/presentation/plans_page.dart) · super_admin_providers.dart (`allPlansProvider`, `upsertPlan`).
- **Problems:** Sheet's 3-column limits row cramped; delete hidden in popup, no confirm; nullable limits unclear (unlimited vs unset); no usage count before delete.
- **Revamp target:** §3.5 plan sheet that stacks the limit fields gracefully and clarifies "unlimited"; a confirm on delete. Flag "academies on this plan" if it needs a query.

#### `features/super_admin/presentation/super_tickets_page.dart`
- **Files:** [super_tickets_page.dart](apps/mobile/lib/features/super_admin/presentation/super_tickets_page.dart) · super_admin_providers.dart (`allTicketsProvider`, `ticketMessagesProvider`, `postStaffReply`, `updateTicket`).
- **Problems:** Bespoke priority `CircleAvatar` (not the badge system); status transitions are a static list with no current-state cue; flat thread; no age/SLA; no sort.
- **Revamp target:** Replace the priority avatar with `AppBadge` tones; make status transitions a clear control showing current state; thread layout matching the support-page thread fix.

---

## 5. Execution sequencing

Work in this order so shared patterns land before the screens that depend on them:

1. **Shells & nav (§4.1)** — define the canonical shell contract + account entry
   point + grouped settings. Everything else sits inside this frame.
2. **Home dashboards (§4.2)** — the §3.4 anatomy; highest-visibility screens.
3. **Establish the shared sub-patterns** by doing one exemplar each, then reusing:
   - the **people-list template** (students_tab) → reuse for coaches, team, etc.
   - the **shared documents section** → apply to student + coach.
   - the **shared assignment section** → apply to all four billing sections.
   - the **shared ticket-thread** → apply to support + super-tickets.
4. **The rest, by area (§4.4 → §4.9).** Each screen is independent once the
   shared patterns exist — they can be parallelized across sessions.

## 6. Definition of done (per screen)

- [ ] Read the screen's model + providers (+ migration if needed); understand every field.
- [ ] Layout follows the relevant §3 anatomy; matches the rest of the app.
- [ ] No color/type/token changes; no new architecture/deps; shared widgets intact.
- [ ] Every capability gate, provider read/write, and `ref.invalidate` preserved.
- [ ] Loading / error / empty states all present via shared widgets.
- [ ] No magic numbers, `withOpacity`, `Colors.black/white`; const + trailing commas.
- [ ] Anything that would need a new query/column/migration is **flagged, not built**.
- [ ] (If the user asks) `flutter analyze` clean + `flutter test` green; type finders resolve.
```

