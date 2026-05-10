import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';

class EventFormPage extends ConsumerStatefulWidget {
  const EventFormPage({super.key});

  @override
  ConsumerState<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends ConsumerState<EventFormPage> {
  final _form = GlobalKey<FormState>();
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

  Future<void> _pickDate(DateTime initial, ValueChanged<DateTime> onPick) async {
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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centers = ref.watch(centersProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<EventKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Kind'),
              items: [
                for (final k in EventKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? EventKind.tournament),
            ),
            const SizedBox(height: 12),
            SportPicker(
              value: _sportId,
              onChanged: (v) => setState(() => _sportId = v),
              centerId: _centerId,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts at *'),
              subtitle: Text(_startsAt.toLocal().toString()),
              trailing: const Icon(Icons.event),
              onTap: () => _pickDate(_startsAt, (v) => setState(() => _startsAt = v)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ends at'),
              subtitle: Text(_endsAt?.toLocal().toString() ?? '—'),
              trailing: const Icon(Icons.event),
              onTap: () => _pickDate(
                _endsAt ?? _startsAt,
                (v) => setState(() => _endsAt = v),
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Registration opens'),
              subtitle: Text(_regOpens?.toLocal().toString() ?? '—'),
              trailing: const Icon(Icons.lock_open),
              onTap: () => _pickDate(
                _regOpens ?? DateTime.now(),
                (v) => setState(() => _regOpens = v),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Registration closes'),
              subtitle: Text(_regCloses?.toLocal().toString() ?? '—'),
              trailing: const Icon(Icons.lock),
              onTap: () => _pickDate(
                _regCloses ?? _startsAt,
                (v) => setState(() => _regCloses = v),
              ),
            ),
            const Divider(),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _centerId,
              decoration: const InputDecoration(labelText: 'Center (optional)'),
              items: [
                const DropdownMenuItem<String?>(
                  child: Text('— None —'),
                ),
                for (final c in centers)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _centerId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _capacity,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Capacity (optional)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _fee,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Fee (₹)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _publish,
              onChanged: (v) => setState(() => _publish = v),
              title: const Text('Publish immediately'),
              subtitle: const Text('Otherwise saved as draft'),
            ),
            const SizedBox(height: 24),
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
