import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/schedule_picker.dart';
import 'package:playhub/features/centers/data/center.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit batch' : 'New batch')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Details -------------------------------------------------------
            const AppSectionHeader(title: 'Details'),
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
                  value: _sportId,
                  onChanged: (v) => setState(() => _sportId = v),
                  centerId: _centerId,
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
              label: 'Coach',
              value: _coachId,
              async: coachesAsync,
              emptyOptionLabel: '— unassigned —',
              optionsOf: (coaches) => coaches,
              idOf: (c) => c.id,
              labelOf: (c) => c.fullName,
              onChanged: (v) => setState(() => _coachId = v),
              onRetry: () => ref.invalidate(coachesProvider),
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
            const AppSectionHeader(title: 'Schedule'),
            const SizedBox(height: AppSpacing.sm),
            SchedulePicker(value: _schedule, onChanged: (s) => _schedule = s),

            // Capacity ------------------------------------------------------
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Capacity'),
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

            // Primary action ------------------------------------------------
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save changes' : 'Create batch'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labeled select backed by an [AsyncValue] list. Keeps a **stable field
/// shape** across loading / error / data so the form never jumps: loading and
/// error both render inside an [InputDecorator] sized like the real dropdown
/// (a thin progress bar that flickered separately is what we're replacing).
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

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Loading…',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
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
