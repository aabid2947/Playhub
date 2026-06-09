import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class EventFormPage extends ConsumerStatefulWidget {
  const EventFormPage({super.key});

  @override
  ConsumerState<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends ConsumerState<EventFormPage> {
  final _form = GlobalKey<FormState>();
  final _df = DateFormat('EEE, dd MMM yyyy');
  final _tf = DateFormat('HH:mm');
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _capacity = TextEditingController();
  final _fee = TextEditingController(text: '0');
  EventKind _kind = EventKind.tournament;
  DateTime _startsAt = DateTime.now().add(const Duration(days: 7));
  DateTime? _endsAt;
  DateTime? _regOpens;
  DateTime? _regCloses;
  String? _centerId;
  String? _sportId;
  bool _publish = false;
  bool _saving = false;
  // Once the user has tried to submit, surface validation (including the
  // cross-field start-before-end rule) live as they adjust dates.
  bool _autoValidate = false;

  @override
  void dispose() {
    for (final c in [_title, _desc, _location, _capacity, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  // Cross-field: an end date is optional, but when set it must be after the
  // start. Returns a user-facing message, or null when the schedule is valid.
  String? get _scheduleError {
    if (_endsAt != null && !_endsAt!.isAfter(_startsAt)) {
      return 'The end must be after the start.';
    }
    return null;
  }

  Future<void> _pickDate(
    DateTime initial,
    ValueChanged<DateTime> onPick,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null) return;
    onPick(DateTime(picked.year, picked.month, picked.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _scheduleError != null) {
      setState(() => _autoValidate = true);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = await ref.read(eventsRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.create(
        title: _title.text.trim(),
        kind: _kind,
        startsAt: _startsAt,
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        sportId: _sportId,
        endsAt: _endsAt,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        centerId: _centerId,
        registrationOpensAt: _regOpens,
        registrationClosesAt: _regCloses,
        capacity: int.tryParse(_capacity.text.trim()),
        feeAmount: double.tryParse(_fee.text.trim()) ?? 0,
        status: _publish ? EventStatus.published : EventStatus.draft,
      );
      ref.invalidate(eventsListProvider);
      if (!mounted) return;
      AppSnackbar.success(
        context,
        _publish ? 'Event published.' : 'Saved as draft.',
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centers = ref.watch(centersProvider).valueOrNull ?? [];
    final scheduleError = _autoValidate ? _scheduleError : null;
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // ── Details ──────────────────────────────────────────────
            const AppSectionHeader(
              title: 'Details',
              icon: Icons.event_note_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _title,
              label: 'Title *',
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<EventKind>(
              label: 'Kind',
              value: _kind,
              items: [
                for (final k in EventKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _kind = v ?? EventKind.tournament),
            ),
            const SizedBox(height: AppSpacing.md),
            SportPicker(
              value: _sportId,
              onChanged: (v) => setState(() => _sportId = v),
              centerId: _centerId,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Schedule ─────────────────────────────────────────────
            const AppSectionHeader(
              title: 'Schedule',
              icon: Icons.calendar_month_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            _DateTimeField(
              label: 'Starts at *',
              value: _startsAt,
              icon: Icons.event_outlined,
              dateFormat: _df,
              timeFormat: _tf,
              enabled: !_saving,
              hasError: scheduleError != null,
              onTap: () =>
                  _pickDate(_startsAt, (v) => setState(() => _startsAt = v)),
            ),
            const SizedBox(height: AppSpacing.md),
            _DateTimeField(
              label: 'Ends at',
              value: _endsAt,
              icon: Icons.event_available_outlined,
              dateFormat: _df,
              timeFormat: _tf,
              enabled: !_saving,
              hasError: scheduleError != null,
              onClear: _endsAt == null
                  ? null
                  : () => setState(() => _endsAt = null),
              onTap: () => _pickDate(
                _endsAt ?? _startsAt,
                (v) => setState(() => _endsAt = v),
              ),
            ),
            if (scheduleError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _FieldHint(text: scheduleError, isError: true),
            ],
            const SizedBox(height: AppSpacing.md),
            _DateTimeField(
              label: 'Registration opens',
              value: _regOpens,
              icon: Icons.lock_open_outlined,
              dateFormat: _df,
              timeFormat: _tf,
              enabled: !_saving,
              onClear: _regOpens == null
                  ? null
                  : () => setState(() => _regOpens = null),
              onTap: () => _pickDate(
                _regOpens ?? _startsAt,
                (v) => setState(() => _regOpens = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _DateTimeField(
              label: 'Registration closes',
              value: _regCloses,
              icon: Icons.lock_outline,
              dateFormat: _df,
              timeFormat: _tf,
              enabled: !_saving,
              onClear: _regCloses == null
                  ? null
                  : () => setState(() => _regCloses = null),
              onTap: () => _pickDate(
                _regCloses ?? _startsAt,
                (v) => setState(() => _regCloses = v),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Location & capacity ──────────────────────────────────
            const AppSectionHeader(
              title: 'Location & capacity',
              icon: Icons.place_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _location,
              label: 'Location',
              enabled: !_saving,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String?>(
              label: 'Center (optional)',
              value: _centerId,
              items: [
                const DropdownMenuItem<String?>(child: Text('— None —')),
                for (final c in centers)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: _saving ? null : (v) => setState(() => _centerId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            // Capacity + fee sit side-by-side on wide layouts and stack to full
            // width when the screen is too narrow to hold both usably.
            _TwoUpRow(
              left: AppFormField(
                controller: _capacity,
                label: 'Capacity (optional)',
                enabled: !_saving,
                keyboardType: TextInputType.number,
              ),
              right: AppFormField(
                controller: _fee,
                label: 'Fee (₹)',
                enabled: !_saving,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Description ──────────────────────────────────────────
            const AppSectionHeader(
              title: 'Description',
              icon: Icons.notes_rounded,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _desc,
              label: 'Details',
              enabled: !_saving,
              maxLines: 5,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Publish ──────────────────────────────────────────────
            const AppSectionHeader(
              title: 'Publish',
              icon: Icons.campaign_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            _PublishChoice(
              publish: _publish,
              enabled: !_saving,
              onChanged: (v) => setState(() => _publish = v),
            ),
          ],
        ),
      ),
      // Pinned, full-width primary action — inline spinner while saving.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.lg),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_publish ? Icons.campaign_outlined : Icons.save_outlined),
            label: Text(
              _saving
                  ? 'Saving…'
                  : (_publish ? 'Publish event' : 'Save draft'),
            ),
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
    );
  }
}

/// A tidy date-time picker field. Renders inside an [InputDecorator] so it
/// reads as a labeled form field, showing the chosen date + time (or a muted
/// placeholder) with a leading icon and an optional clear affordance.
class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.icon,
    required this.dateFormat,
    required this.timeFormat,
    required this.onTap,
    this.onClear,
    this.enabled = true,
    this.hasError = false,
  });

  final String label;
  final DateTime? value;
  final IconData icon;
  final DateFormat dateFormat;
  final DateFormat timeFormat;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool enabled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final local = value?.toLocal();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        errorText: hasError ? '' : null,
        prefixIcon: Icon(
          icon,
          color: enabled ? scheme.onSurfaceVariant : scheme.outline,
        ),
        suffixIcon: onClear != null && enabled
            ? IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              )
            : const Icon(Icons.edit_calendar_outlined),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: local == null
              ? Text(
                  'Tap to set',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Row(
                  children: [
                    Text(
                      dateFormat.format(local),
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '· ${timeFormat.format(local)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A visible draft-vs-publish choice. A [SegmentedButton] makes the publish
/// state explicit (vs. a buried toggle), with a one-line caption explaining
/// what each option does.
class _PublishChoice extends StatelessWidget {
  const _PublishChoice({
    required this.publish,
    required this.onChanged,
    this.enabled = true,
  });

  final bool publish;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.drafts_outlined),
                  label: Text('Save as draft'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.campaign_outlined),
                  label: Text('Publish now'),
                ),
              ],
              selected: {publish},
              onSelectionChanged:
                  enabled ? (s) => onChanged(s.first) : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            publish
                ? 'The event is visible and open for registration once the '
                    'registration window allows.'
                : 'The event stays hidden until you publish it later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small caption shown under a field — muted by default, danger-toned when
/// it carries a validation error.
class _FieldHint extends StatelessWidget {
  const _FieldHint({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError
        ? AppSemanticColors.of(context).danger
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isError) ...[
          Icon(Icons.error_outline, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
        ],
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Lays two fields side-by-side on wide layouts and stacks them to full width
/// when the screen is too narrow to hold both inputs usably.
class _TwoUpRow extends StatelessWidget {
  const _TwoUpRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two-up only when each half clears a usable minimum width.
        final half = (constraints.maxWidth - AppSpacing.md) / 2;
        if (half < 140) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              const SizedBox(height: AppSpacing.md),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
