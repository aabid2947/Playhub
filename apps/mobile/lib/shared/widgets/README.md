# PlayHub Mobile Design System

Shared widgets + design tokens used by every screen in `apps/mobile`. All
widgets are **thin wrappers** over Material primitives so existing widget
tests (e.g. `find.byType(Card)`, `find.byType(TextField)`,
`find.byType(ListTile)`) continue to resolve.

## Tokens

Import: `package:playhub/core/design_tokens.dart`

- `AppSpacing` — `xs(4) sm(8) md(12) lg(16) xl(24) xxl(32)`
- `AppRadius` — `sm(8) md(12) lg(16) xl(20) pill(999)`
- `AppDuration` — `fast(150ms) normal(250ms) slow(400ms)`
- `AppElevation` — `none(0) low(1) med(3) high(8)`
- `AppPalette` — `brandPrimary brandSecondary success warning danger info
  gray50..gray900 surfaceTintLight surfaceTintDark`
- `AppBreakpoints` — `phone(600) tablet(900) desktop(1200)`

## Theme

`AppTheme.light()` / `AppTheme.dark()` — call from `MaterialApp.theme` /
`darkTheme`. Brand seed is `AppPalette.brandPrimary` (#16A34A). Typography
uses Google Inter via `google_fonts`.

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
auto-chevron when `onTap` is set. Renders a real `ListTile`.

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
