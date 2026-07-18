# SKILLS.md — PlayHub mobile UI/UX upgrade playbook

> **Audience:** a future Claude (or dev) told *"make this screen sleek and
> production-ready."* This is the how. Read it, then upgrade the screen you were
> given by following the checklist — don't freelance a new visual language.
>
> **Companions:** [design-system reference](lib/shared/widgets/README.md) ·
> [project rules](../../CLAUDE.md) · [file map](../../repo_structure.md).

PlayHub is a multi-tenant sports-academy SaaS (India-first). As of 2026-06-09 the
look is the **"Sports-Light" v1 concept the client approved** — energetic and
sporty, not flat-corporate: an **energetic orange** (`#FF6A2C`) leads every
call-to-action, a **deep navy** (`#0F2540`) is the ink, a broadcast **blue**
(`#1763E0`) accents sparingly, on clean near-white surfaces. Gradient hero bands,
colorful feature cards, soft-shadowed cards. **Light theme only** (no dark).

> **⚠️ Skin reversed 2026-06-09 — see [UI_REVAMP_V1.md](../../UI_REVAMP_V1.md)
> (authoritative).** The brand recolored **violet → orange + navy**, and the app
> is now **light-only**. Color/type are still driven solely from `colors.ts` /
> `design_tokens.dart` / `theme.dart` (the v1 palette) — don't hard-code; consume
> tokens. Wherever this doc still says "violet" / "both themes ship", read
> "orange + navy" / "light only". New v1 widgets: `AppGradientHeader`,
> `AppFeatureCard`, `AppPillTabs`, `AppAvatar`, `AppLabeledProgress`,
> `AppMiniBarChart` (barrel `shared/widgets/widgets.dart`).

---

## 0. Guardrails — do not break these while polishing

These are load-bearing. Violating one turns a polish task into a bug.

1. **Shared widgets are thin wrappers over Material primitives on purpose** —
   so `find.byType(Card)`, `find.byType(ListTile)`, `find.byType(TextField)`
   in the widget tests still resolve. Keep using `AppCard` / `AppListTile` /
   `AppFormField`; **don't** replace them with bespoke `Container`s that no
   longer render a real `Card`/`ListTile`. Run `flutter test` after.
2. **No new architecture for a coat of paint.** No `freezed`/codegen, no
   `@riverpod`, no state-management lib, no service layer. Match the
   hand-written model/provider idiom already in the file.
3. **UI never offers what the backend will reject.** Visibility of actions is
   gated by the capability mirror
   ([capabilities.dart](lib/features/auth/data/capabilities.dart)) — e.g.
   `ref.watch(capabilitiesProvider).manageCoaches`. RLS is the real gate;
   the UI must mirror it. When you restyle a gated action, **keep the gate.**
4. **No hard-coded colors, spacing, radii, or font sizes.** Everything comes
   from `design_tokens.dart` / the theme. A raw `Color(0xFF…)`,
   `EdgeInsets.all(32)`, or `fontSize: 18` in a screen is a regression.
5. **Keep `flutter analyze` clean** (`very_good_analysis`, strict). No
   `withOpacity` (use `.withValues(alpha:)`), trailing commas, `const` where
   possible.
6. **Light only ships** (v1). Still never hard-code `Colors.black/white` for
   text/surfaces — use `colorScheme.*` / `AppSemanticColors` / tokens so the
   navy-on-near-white reads correctly and a future dark re-enable stays sane.
   (`Colors.white` text *is* correct on a gradient hero band.)

---

## 1. The design language in 30 seconds

| Aspect | Decision |
|---|---|
| **Primary (vivid violet `#9933FF`)** | Everything branded: actions, primary buttons, selected/active, nav selection. `colorScheme.primary`. |
| **Accent (magenta `#E95FE9`)** | Sparingly — brand mark / hero gradients, highlights. `AppPalette.brandSecondary` / `brandGradient`. |
| **Surfaces** | Neutral. Light: white cards on a `gray50` page. Dark: near-black `ink900` cards on an `ink950` page (Tailwind "zinc"). Both ship (follows the device). |
| **Separation** | A hairline `outlineVariant` border — **not** drop shadows. Low-chrome, flat, outlined. |
| **Status** | `AppSemanticColors.of(context)` → success / warning / danger / info (each adapts to dark). |
| **Type** | Inter. Display/headlines tighten tracking; labels open up; body at 1.5 line-height. |
| **Shape** | Cards `lg` (16) · buttons/inputs `md` (12) · sheets `xxl` (28) · pills `pill`. |
| **Motion** | Subtle. `AppDuration.fast/normal`. Shimmer for loading. No bouncy/parallax. |

If a screen looks "designed" but breaks the table above, the table wins.

---

## 2. Cheat-sheet

```dart
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/widgets.dart';
```

**Spacing** `AppSpacing.xs/sm/md/lg/xl/xxl/xxxl` → `4 8 12 16 24 32 48`
**Radius** `AppRadius.sm/md/lg/xl/xxl/pill` → `8 12 16 20 28 999`
**Colors** `colorScheme.*` for brand/surface; `AppSemanticColors.of(context).{success,warning,danger,info}` (+ `*Container`, `on*`) for status.
**Type** `Theme.of(context).textTheme.*` (see §5). `AppType.*` only for a one-off weight/tracking.
**Gradients** `AppPalette.brandGradient` (violet→magenta sweep) for brand marks / hero headers.

**Widgets** (barrel: `shared/widgets/widgets.dart`):
`AppCard` · `AppListTile` · `AppStatTile` · `AppBadge(tone:)` ·
`AppSectionHeader` · `AppEmptyState` · `AppErrorView` · `AppLoading` /
`AppSkeleton` / `AppSkeletonList` · `AppFormField` · `AppSnackbar.{success,error,info}`.

---

## 3. The screen-upgrade checklist

Work top-to-bottom. Most screens fail items 1–4 — that's where the lift is.

- [ ] **1. Replace raw async states.** `CircularProgressIndicator()` →
      `AppLoading()` or `AppSkeletonList()`. `Center(child: Text(error))` →
      `AppErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(...))`.
      Hand-rolled empty `Column` → `AppEmptyState(...)`.
- [ ] **2. Kill magic numbers.** Every `EdgeInsets.all(32)`, `SizedBox(height: 12)`,
      `fontSize:`, raw radius → a token. `vertical: 8` → `AppSpacing.sm`.
- [ ] **3. Adopt the shared widgets.** Raw `ListTile` → `AppListTile`. Raw
      `Card` → `AppCard`. Raw status pill → `AppBadge`. Inline `TextFormField`
      → `AppFormField`.
- [ ] **4. Use theme colors, not literals/`AppPalette` constants.** Status
      colors via `AppSemanticColors.of(context)`. Brand via `colorScheme`.
- [ ] **5. Establish hierarchy.** Group with `AppSectionHeader`. Page padding
      `AppSpacing.lg`. Consistent gaps (`AppSpacing.md` between cards). Don't
      let a screen be one flat undifferentiated list (see the home dashboard).
- [ ] **6. Right text role for the job** (§5). Don't restyle `bodyMedium` into a
      title — use `titleMedium`.
- [ ] **7. Tap targets ≥ 48px**, tooltips on icon-only buttons, `Semantics`
      labels on meaningful icons.
- [ ] **8. Preserve capability gates & provider wiring** (`caps.*`, `ref.invalidate`
      after writes). Polish is visual — don't change data flow.
- [ ] **9. `flutter analyze` clean + `flutter test` green.**

---

## 4. Before / After recipes

### 4a. Async states — the most common gap

Real `centers_tab.dart` shipped raw states. Upgrade:

```dart
// BEFORE
body: centersAsync.when(
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, _) => Center(child: Text(friendlyError(e))),
  data: (centers) {
    if (centers.isEmpty) return const _EmptyState(); // 30 hand-rolled lines
    return RefreshIndicator(/* raw ListTile list */);
  },
),

// AFTER
body: centersAsync.when(
  loading: () => const AppSkeletonList(),
  error: (e, _) => AppErrorView(
    message: friendlyError(e),
    onRetry: () => ref.invalidate(centersProvider),
  ),
  data: (centers) {
    if (centers.isEmpty) {
      return AppEmptyState(
        icon: Icons.location_city_outlined,
        title: 'No centers yet',
        subtitle: 'Add the first physical location for your academy.',
        actionLabel: 'New center',
        onAction: () => _openForm(context),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(centersProvider),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: centers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final c = centers[i];
          return AppListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(c.name),
            subtitle: Text([
              if (c.city != null) c.city!,
              if (!c.isActive) 'Inactive',
            ].join(' • ')),
            onTap: () => _openForm(context, existing: c),
          );
        },
      ),
    );
  },
),
```

This single migration removes a `_EmptyState` boilerplate class, gives a
shimmer skeleton, a retry button, dark-mode-correct colors, and a tinted
leading icon — across *every* list screen that still does it the old way.

### 4b. List screen anatomy

`Scaffold` → `body: async.when(...)` → `RefreshIndicator` →
`ListView.separated` of `AppListTile`. FAB is `FloatingActionButton.extended`,
**gated** when it mutates: `caps.manageX ? FAB : null`. Empty → `AppEmptyState`.

### 4c. Form screen anatomy

`Form(key:)` → `ListView` padded `AppSpacing.lg` → `AppFormField`s spaced
`AppSpacing.md` → a pinned/`bottom` primary `FilledButton` (full-width, busy →
inline spinner). Group long forms with `AppSectionHeader`. On success
`AppSnackbar.success(context, 'Saved.')` + `ref.invalidate(listProvider)` + pop.

### 4d. Dashboard / KPIs

Greeting/hero first, then a 2-up grid of `AppStatTile`, then grouped
`AppListTile` actions under `AppSectionHeader`s — never one 12-item flat list.
For a hero header use a gradient container (`AppPalette.brandGradient`) with
`AppRadius.lg`, white-on-gradient text.

### 4e. Status pills

```dart
AppBadge(text: 'Paid',     tone: AppBadgeTone.success);
AppBadge(text: 'Overdue',  tone: AppBadgeTone.danger);
AppBadge(text: 'Pending',  tone: AppBadgeTone.warning);
AppBadge(text: 'Trial',    tone: AppBadgeTone.info);
```
Map domain status → tone in one helper; never color a `Text` by hand.

---

## 5. Typography — which role for what

| Role | Use for |
|---|---|
| `headlineMedium/Small` | Screen titles inside the body (e.g. "Sign in"). |
| `titleLarge` | AppBar title, card titles, sheet headers. |
| `titleMedium` | Sub-section / list group titles, primary list text. |
| `bodyLarge` | Emphasized body, list tile primary text. |
| `bodyMedium` | Default paragraph/body. |
| `bodySmall` | Captions, metadata, KPI labels. |
| `labelLarge` | Buttons (already themed). |
| `labelSmall` (+ wide tracking) | Overlines, `AppSectionHeader`, badges. |

Never set `fontSize`/`fontWeight` inline to fake a role — pick the role. One-off
tweak? `style.copyWith(fontWeight: AppType.semibold)`.

---

## 6. Color usage rules

- **Action / brand / selected / nav-selection** → `colorScheme.primary` (+
  `onPrimary`, `primaryContainer`). Vivid violet `#9933FF`.
- **Accent** → `AppPalette.brandSecondary` (magenta) + `brandGradient`,
  used sparingly for brand marks / hero gradients.
- **Status** → `AppSemanticColors.of(context)`:
  `.success`/`.danger`/… for fg (icon/text/border), `.<tone>Container` for the
  soft background, `.on<Tone>` for text on a **filled** swatch.
- **Surfaces / text** → `colorScheme.surface`, `onSurface`,
  `onSurfaceVariant` (secondary text), `outlineVariant` (borders).
- **Never** `AppPalette.success` directly in a screen (fixed light value) — go
  through the extension so dark mode is right. `AppPalette` raw constants are
  for the theme/tokens layer only, plus `brandGradient` for brand marks.

---

## 7. Spacing & shape rhythm

- Page padding: `AppSpacing.lg` (16). Section gaps: `AppSpacing.xl` (24).
  Between cards: `AppSpacing.md` (12). Inside a card: `AppSpacing.lg`.
- Hero/empty-state vertical breathing room: `AppSpacing.xxl`/`xxxl`.
- Cards `AppRadius.lg`, buttons/inputs `md`, bottom sheets `xxl`, pills `pill`.
- Prefer a consistent vertical rhythm over pixel-tuning individual gaps.

---

## 8. Accessibility (don't skip — it's part of "production-ready")

- Min tap target **48×48** (buttons already meet it; custom `InkWell`s must).
- Icon-only buttons get a `tooltip`. Meaningful standalone icons get
  `Semantics(label: …)`.
- Don't encode meaning in color alone — pair status color with text/icon
  (`AppBadge` already does).
- Respect text scaling: avoid fixed-height text containers that clip; let rows
  wrap. Test at large font scale.
- Maintain contrast: body text on surface uses `onSurface`/`onSurfaceVariant`
  (already AA on both themes). Don't put `gray400` text on white.

---

## 9. Anti-patterns (reject these in review)

- ❌ Bespoke `Container` with `boxShadow` + manual radius instead of `AppCard`.
- ❌ `Color(0xFF…)`, `EdgeInsets.all(24)`, `fontSize: 16` in a screen.
- ❌ `withOpacity(…)` (deprecated) — use `.withValues(alpha: …)`.
- ❌ A raw `CircularProgressIndicator`/error `Text` when `AppLoading`/
  `AppErrorView` exist.
- ❌ Showing a mutating action without its `caps.*` gate.
- ❌ Replacing an `AppListTile`/`AppCard` with something that no longer renders
  a real `ListTile`/`Card` (breaks widget-type finders in tests).
- ❌ Gradients/shadows everywhere "to look modern." Restraint reads as premium.

---

## 10. Verify before claiming done

```bash
cd apps/mobile
flutter analyze        # must be clean
flutter test           # widget/unit; type-based finders must still resolve
```

If you changed a token's meaning or the theme, also sanity-check a couple of
screens in both brightnesses (the role dashboards exercise the most widgets).

---

## 11. Optional: promote this to a slash-command skill

This file is a plain playbook so it's greppable and reviewable. If you want
`/ui-polish <screen>` as a command, copy the checklist into
`.claude/skills/ui-polish/SKILL.md` with frontmatter and have it reference this
file as the source of truth. Keep **one** canonical copy — this one.
