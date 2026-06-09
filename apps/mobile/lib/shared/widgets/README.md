# PlayHub Mobile Design System

Shared widgets + design tokens used by every screen in `apps/mobile`. All
widgets are **thin wrappers** over Material primitives so existing widget
tests (e.g. `find.byType(Card)`, `find.byType(TextField)`,
`find.byType(ListTile)`) continue to resolve.

## Tokens

Import: `package:playhub/core/design_tokens.dart`

- `AppSpacing` — `xs(4) sm(8) md(12) lg(16) xl(24) xxl(32) xxxl(48)`
- `AppRadius` — `sm(8) md(12) lg(16) xl(20) xxl(28) pill(999)`
- `AppDuration` — `fast(150ms) normal(250ms) slow(400ms)`
- `AppElevation` — `none(0) low(1) med(3) high(8)`
- `AppType` — font family + weights (`regular/medium/semibold/bold`) + tracking
  (`trackingTight -0.5` … `trackingWider 0.8`). The type scale itself lives on
  `Theme.of(context).textTheme`; reach for `AppType` only for a one-off
  weight/tracking tweak.
- `AppPalette` — **v1 "Sports-Light" (light-only): `brandPrimary` orange
  `#FF6A2C`** (+ `brandPrimaryDark/Soft/Muted`) · `brandSecondary`/`accent` blue
  `#1763E0` · `ink` navy `#0F2540` + `inkSoft` · `textPrimary/Secondary/Muted` ·
  `pageBackground #F4F7FB` / `surface #FFFFFF` / `surfaceAlt` / `borderLight` ·
  `success warning danger info` · `brandGradient` (orange) · `navyGradient` ·
  `categorySwatch` (sport accents). `ink950..ink100` dark neutrals are dormant.
- `AppShadows` — `card` (default soft lift) · `raised` · `floating` (pinned bars).
- `AppSemanticColors` — **theme-aware** success/warning/danger/info. Read via
  `AppSemanticColors.of(context)`; each tone exposes `<tone>` (fg color),
  `<tone>Container` (bg tint), and `on<Tone>` (text on a filled swatch).
- `AppBreakpoints` — `phone(600) tablet(900) desktop(1200)`

> Use `AppSemanticColors.of(context)` for status colors — **not** the raw
> `AppPalette.success/...` constants. The extension adapts to dark mode; the
> constants are fixed light-surface values (and are what the extension is
> built from).

## Theme

`AppTheme.light()` / `AppTheme.dark()` — wired into `MaterialApp.theme` /
`darkTheme`. Material 3, Google Inter via `google_fonts`.

- **Color** — vivid violet. Violet leads (`colorScheme.primary` — actions,
  brand, nav selection); a violet→magenta gradient (`AppPalette.brandGradient`)
  covers brand marks. Surfaces are hand-tuned neutrals: white cards on a `gray50` page
  (light); near-black `ink900` cards on an `ink950` page (dark, Tailwind "zinc").
  Separation comes from a hairline `outlineVariant` border, not shadows.
  **Both light + dark ship** — `themeMode` follows the device.
- **Type** — display/headlines tighten their tracking; labels open up; body
  runs at 1.5 line-height.
- **Status colors** come from the `AppSemanticColors` theme extension,
  registered on `ThemeData.extensions`.

See [SKILLS.md](../../../SKILLS.md) — the screen-by-screen UI/UX upgrade playbook.

## Widgets

Barrel: `import 'package:playhub/shared/widgets/widgets.dart';`

### `AppCard`
Outlined card with `AppRadius.lg`, optional ripple via `onTap`. Renders a
real `Card`.

```dart
AppCard(onTap: () {}, child: Text('Hello'));
```

### `AppListTile`
Wrapper over `ListTile` with tinted leading icon container and
auto-chevron when `onTap` is set. Renders a real `ListTile`. Pass
`wrapLeading: false` when the leading is already a self-contained visual (an
avatar / `CircleAvatar`) that shouldn't sit in the tinted icon box.

```dart
AppListTile(
  leading: const Icon(Icons.person),
  title: const Text('Profile'),
  subtitle: const Text('View and edit'),
  onTap: () {},
);
```

### `AppStatTile`
KPI tile rendered inside an `AppCard`. Icon + label + headline value, with
an optional `trend` chip.

```dart
AppStatTile(icon: Icons.people, label: 'Athletes', value: '128', trend: '+12%');
```

### `AppEmptyState`
Centered empty placeholder with icon, title, optional subtitle and CTA.

```dart
AppEmptyState(
  icon: Icons.inbox,
  title: 'No results',
  subtitle: 'Try adjusting your filters.',
  actionLabel: 'Reset',
  onAction: reset,
);
```

### `AppErrorView`
Centered error view with optional `Retry`. Defaults title to
`Something went wrong`.

```dart
AppErrorView(message: e.toString(), onRetry: refresh);
```

### `AppLoading`, `AppSkeleton`, `AppSkeletonList`
Loading indicators. `AppSkeleton` is an animated shimmer box;
`AppSkeletonList` is a column of N (default 6) rows.

```dart
AppLoading(label: 'Loading…');
AppSkeleton(width: 200, height: 16);
AppSkeletonList(count: 4);
```

### `AppFormField`
Labeled text input. Internally renders a `TextFormField` (and thus a
`TextField`) so type-based finders still resolve.

```dart
AppFormField(
  controller: _email,
  label: 'Email',
  hint: 'you@club.com',
  keyboardType: TextInputType.emailAddress,
  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
);
```

### `AppDropdownField`
Labeled select that mirrors `AppFormField`'s label-above style, so a form
mixing text inputs and dropdowns reads consistently. Renders a real
`DropdownButtonFormField`.

```dart
AppDropdownField<FeeType>(
  label: 'Frequency',
  value: _type,
  items: FeeType.values
      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
      .toList(),
  onChanged: (v) => setState(() => _type = v ?? FeeType.monthly),
);
```

### `AppDateField`
Labeled, tappable date field matching `AppFormField`'s label-above style. The
caller owns the value + `showDatePicker`; this renders the field and fires
`onTap`. Shows `placeholder` when `value` is null.

```dart
AppDateField(label: 'Date of birth', value: _dob, onTap: _pickDob);
```

### `AppSectionHeader`
Uppercase section heading with optional trailing action.

```dart
AppSectionHeader(title: 'Upcoming sessions', trailing: TextButton(...));
```

### `AppBadge`
Tinted pill label with a tone enum.

```dart
AppBadge(text: 'Active', tone: AppBadgeTone.success);
```

### `AppSnackbar`
Static helpers, not a widget:

```dart
AppSnackbar.success(context, 'Saved.');
AppSnackbar.error(context, 'Could not save.');
AppSnackbar.info(context, 'Heads up.');
```

### `BrandWordmark`
The two-tone "PlayHub" wordmark — `Play` in ink, `Hub` in brand violet. One
source of truth for the wordmark (auth header + primary app-bar branding). Pass
`style:` to resize.

### `CountBadgeIcon`
An icon with a capped notification-count badge (`9+` by default; plain icon at
zero). Used for nav "Alerts" destinations.

```dart
CountBadgeIcon(icon: Icons.notifications_outlined, count: unread);
```
