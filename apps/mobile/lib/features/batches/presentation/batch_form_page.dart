import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/schedule_picker.dart';
import 'package:playhub/features/centers/data/center.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class BatchFormPage extends ConsumerStatefulWidget {
  const BatchFormPage({super.key, this.existing});

  final Batch? existing;

  @override
  ConsumerState<BatchFormPage> createState() => _BatchFormPageState();
}

class _BatchFormPageState extends ConsumerState<BatchFormPage> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _ageGroup = TextEditingController(
    text: widget.existing?.ageGroup ?? '',
  );
  late final _capacity = TextEditingController(
    text: widget.existing?.capacity?.toString() ?? '',
  );

  String? _centerId;
  String? _coachId;
  String? _sportId;
  String? _skillLevel;
  late BatchSchedule _schedule;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _centerId = widget.existing?.centerId;
    _coachId = widget.existing?.coachId;
    _sportId = widget.existing?.sportId;
    _skillLevel = widget.existing?.skillLevel;
    _schedule = widget.existing?.schedule ?? const BatchSchedule();
  }

  @override
  void dispose() {
    _name.dispose();
    _ageGroup.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // A batch must have a sport — head_coach/coach RLS (batch_in_my_sport), the
    // performance rubric and sport filtering all key off it. The picker's
    // validator covers "sports exist but none picked"; this backstops the "no
    // sports configured" empty state, where the picker renders a hint (not a
    // field) so the validator can't run.
    if (_sportId == null) {
      // Coaches/head_coaches can't enable sports themselves (that's admin /
      // center_admin), so point them at an admin instead of Settings → Sports.
      final role = ref.read(currentProfileProvider).valueOrNull?.role;
      final scoped = role == 'head_coach' || role == 'coach';
      AppSnackbar.error(
        context,
        scoped
            ? 'Pick a sport for this batch — ask an admin to enable a sport you can coach first.'
            : 'Pick a sport for this batch — enable one in Settings → Sports first.',
      );
      return;
    }
    // A batch must have a coach — the coach app only shows batches its user
    // staffs, so a coachless batch is invisible and can't have attendance
    // marked. The picker's validator covers the data state; this backstops
    // loading/error (and reminds where to add one if the academy has none).
    if (_coachId == null) {
      AppSnackbar.error(
        context,
        'Assign a coach for this batch — add one in the Coaches tab first if you have none.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'sport_id': _sportId,
        'age_group': _ageGroup.text.trim().isEmpty
            ? null
            : _ageGroup.text.trim(),
        'capacity': _capacity.text.trim().isEmpty
            ? null
            : int.tryParse(_capacity.text.trim()),
        'center_id': _centerId,
        'coach_id': _coachId,
        'skill_level': _skillLevel,
        'schedule': _schedule.toMap(),
      };
      if (isEdit) {
        await updateBatch(ref, widget.existing!.id, patch);
      } else {
        await createBatch(ref, patch);
      }
      if (!mounted) return;
      AppSnackbar.success(context, isEdit ? 'Batch updated.' : 'Batch created.');
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centresAsync = ref.watch(centersProvider);
    final coachesAsync = ref.watch(coachesProvider);
    // A head_coach / coach may only tag a batch with one of their own sports
    // (RLS rejects the rest), so restrict the picker for them. Other roles see
    // the full center/academy list (null = no restriction). Empty-while-loading
    // is safe — it just shows the "no sports" hint until the future resolves.
    final role = ref.watch(currentProfileProvider).valueOrNull?.role;
    final sportScoped = role == 'head_coach' || role == 'coach';
    final restrictSports = sportScoped
        ? (ref.watch(mySportIdsProvider).valueOrNull ?? const <String>[]).toSet()
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit batch' : 'New batch')),
      // Pinned, full-width primary action (archetype D) — inline spinner while
      // saving. A floating shadow lifts the bar off the scrolling form below it.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: AppShadows.floating,
        ),
        child: SafeArea(
          minimum: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _busy
                    ? 'Saving…'
                    : (isEdit ? 'Save changes' : 'Create batch'),
              ),
              onPressed: _busy ? null : _save,
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Details -------------------------------------------------------
            const AppSectionHeader(
              title: 'Details',
              icon: Icons.groups_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _name,
              label: 'Batch name *',
              hint: 'e.g. U-15 Evening',
              prefixIcon: const Icon(Icons.groups_outlined),
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            // Sport + age group stack gracefully on narrow widths.
            LayoutBuilder(
              builder: (context, constraints) {
                final sport = SportPicker(
                  label: 'Sport *',
                  value: _sportId,
                  onChanged: (v) => setState(() => _sportId = v),
                  centerId: _centerId,
                  restrictToSportIds: restrictSports,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                );
                final ageGroup = AppFormField(
                  controller: _ageGroup,
                  label: 'Age group',
                  hint: '6-10, U-15',
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                );
                if (constraints.maxWidth < 360) {
                  return Column(
                    children: [
                      sport,
                      const SizedBox(height: AppSpacing.md),
                      ageGroup,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sport),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: ageGroup),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _AsyncDropdownField<Centre>(
              label: 'Center',
              value: _centerId,
              async: centresAsync,
              emptyOptionLabel: '— none —',
              // Inactive centers can't take new assignments; hide them.
              optionsOf: (centres) => centres.where((c) => c.isActive).toList(),
              idOf: (c) => c.id,
              labelOf: (c) => c.name,
              onChanged: (v) => setState(() => _centerId = v),
              onRetry: () => ref.invalidate(centersProvider),
            ),
            const SizedBox(height: AppSpacing.md),
            _AsyncDropdownField<Coach>(
              label: 'Coach *',
              value: _coachId,
              async: coachesAsync,
              emptyOptionLabel: '— select a coach —',
              optionsOf: (coaches) => coaches,
              idOf: (c) => c.id,
              labelOf: (c) => c.fullName,
              onChanged: (v) => setState(() => _coachId = v),
              onRetry: () => ref.invalidate(coachesProvider),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String>(
              label: 'Skill level',
              value: _skillLevel,
              items: const [
                DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
                DropdownMenuItem(
                  value: 'intermediate',
                  child: Text('Intermediate'),
                ),
                DropdownMenuItem(value: 'advanced', child: Text('Advanced')),
                DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _skillLevel = v),
            ),

            // Schedule ------------------------------------------------------
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(
              title: 'Schedule',
              icon: Icons.event_repeat_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            SchedulePicker(value: _schedule, onChanged: (s) => _schedule = s),

            // Capacity ------------------------------------------------------
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(
              title: 'Capacity',
              icon: Icons.event_seat_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _capacity,
              label: 'Maximum students',
              hint: 'Leave blank for no limit',
              prefixIcon: const Icon(Icons.event_seat_outlined),
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _busy ? null : _save(),
            ),
            // Tail spacing so the last field clears the pinned save bar.
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// A labeled select backed by an [AsyncValue] list. Keeps a **stable field
/// shape** across loading / error / data so the form never jumps: loading
/// shows a calm skeleton bar and error a retry row, both inside an
/// [InputDecorator] sized like the real dropdown — no separate spinner that
/// flickers in and out as the future resolves.
class _AsyncDropdownField<T> extends StatelessWidget {
  const _AsyncDropdownField({
    required this.label,
    required this.value,
    required this.async,
    required this.emptyOptionLabel,
    required this.optionsOf,
    required this.idOf,
    required this.labelOf,
    required this.onChanged,
    required this.onRetry,
    this.validator,
  });

  final String label;
  final String? value;
  final AsyncValue<List<T>> async;

  /// Label for the leading "clear selection" item (e.g. "— none —").
  final String emptyOptionLabel;

  /// Maps the loaded list to the selectable options (e.g. active-only).
  final List<T> Function(List<T>) optionsOf;
  final String Function(T) idOf;
  final String Function(T) labelOf;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRetry;

  /// Optional validator (runs only in the data state; loading/error render a
  /// placeholder, so callers requiring a value must backstop at save time).
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => _FieldShell(
        label: label,
        child: const _LoadingRow(),
      ),
      error: (e, _) => _FieldShell(
        label: label,
        child: _ErrorRow(message: friendlyError(e), onRetry: onRetry),
      ),
      data: (rows) {
        final options = optionsOf(rows);
        return AppDropdownField<String>(
          label: label,
          value: value,
          validator: validator,
          items: [
            DropdownMenuItem<String>(child: Text(emptyOptionLabel)),
            for (final r in options)
              DropdownMenuItem<String>(value: idOf(r), child: Text(labelOf(r))),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

/// Label-above + framed [InputDecorator] body, matching [AppDropdownField]'s
/// shape so the loading/error placeholder occupies the same vertical space.
class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: AppType.semibold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        InputDecorator(
          decoration: const InputDecoration(),
          child: child,
        ),
      ],
    );
  }
}

/// A calm skeleton placeholder occupying the field's body — a single muted bar
/// the height of the dropdown's text. Steadier than a spinner (which pops in
/// and out), so the field doesn't flicker while the options load.
class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Icon(
          Icons.arrow_drop_down,
          color: scheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = AppSemanticColors.of(context).danger;
    return Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: danger),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: danger),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
