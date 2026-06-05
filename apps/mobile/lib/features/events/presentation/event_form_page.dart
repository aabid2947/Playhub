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
  final _df = DateFormat('EEE, dd MMM yyyy · HH:mm');
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

  @override
  void dispose() {
    for (final c in [_title, _desc, _location, _capacity, _fee]) {
      c.dispose();
    }
    super.dispose();
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
    if (!_form.currentState!.validate()) return;
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
          context, _publish ? 'Event published.' : 'Saved as draft.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dateRow({
    required String label,
    required DateTime? value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Builder(
      builder: (context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(
          value == null ? '—' : _df.format(value.toLocal()),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: value == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
              ),
        ),
        trailing: Icon(icon),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final centers = ref.watch(centersProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const AppSectionHeader(title: 'Event details'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _title,
              label: 'Title *',
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
              onChanged: (v) =>
                  setState(() => _kind = v ?? EventKind.tournament),
            ),
            const SizedBox(height: AppSpacing.md),
            SportPicker(
              value: _sportId,
              onChanged: (v) => setState(() => _sportId = v),
              centerId: _centerId,
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Schedule'),
            const SizedBox(height: AppSpacing.xs),
            _dateRow(
              label: 'Starts at *',
              value: _startsAt,
              icon: Icons.event,
              onTap: () =>
                  _pickDate(_startsAt, (v) => setState(() => _startsAt = v)),
            ),
            _dateRow(
              label: 'Ends at',
              value: _endsAt,
              icon: Icons.event,
              onTap: () => _pickDate(
                _endsAt ?? _startsAt,
                (v) => setState(() => _endsAt = v),
              ),
            ),
            _dateRow(
              label: 'Registration opens',
              value: _regOpens,
              icon: Icons.lock_open,
              onTap: () => _pickDate(
                _regOpens ?? _startsAt,
                (v) => setState(() => _regOpens = v),
              ),
            ),
            _dateRow(
              label: 'Registration closes',
              value: _regCloses,
              icon: Icons.lock,
              onTap: () => _pickDate(
                _regCloses ?? _startsAt,
                (v) => setState(() => _regCloses = v),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Location & capacity'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(controller: _location, label: 'Location'),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String?>(
              label: 'Center (optional)',
              value: _centerId,
              items: [
                const DropdownMenuItem<String?>(child: Text('— None —')),
                for (final c in centers)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _centerId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _capacity,
                    label: 'Capacity (optional)',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppFormField(
                    controller: _fee,
                    label: 'Fee (₹)',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Description'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _desc,
              label: 'Details',
              maxLines: 5,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: _publish,
                onChanged: (v) => setState(() => _publish = v),
                title: const Text('Publish immediately'),
                subtitle: const Text('Otherwise saved as draft'),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
