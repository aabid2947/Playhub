import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/academy/data/academy.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';

class AcademySettingsPage extends ConsumerStatefulWidget {
  const AcademySettingsPage({super.key});

  @override
  ConsumerState<AcademySettingsPage> createState() =>
      _AcademySettingsPageState();
}

class _AcademySettingsPageState extends ConsumerState<AcademySettingsPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _website = TextEditingController();
  final _newSport = TextEditingController();
  final _grace = TextEditingController();
  final _prefix = TextEditingController();
  String _latePolicy = 'one_time';
  bool _busy = false;
  String? _message;
  bool _isError = false;
  Academy? _loaded;
  String? _logo;
  List<String> _sports = const [];
  TimeOfDay? _open;
  TimeOfDay? _close;
  List<DateTime> _holidays = const [];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _website.dispose();
    _newSport.dispose();
    _grace.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _hydrate(Academy a) {
    if (_loaded?.id == a.id) return;
    _loaded = a;
    _name.text = a.name;
    _email.text = a.email ?? '';
    _phone.text = a.phone ?? '';
    _address.text = a.address ?? '';
    _city.text = a.city ?? '';
    _website.text = a.website ?? '';
    _logo = a.logo;
    _sports = List.of(a.sportsOffered);
    _open = _parseTime(a.hoursOpen);
    _close = _parseTime(a.hoursClose);
    _holidays = List.of(a.holidays);
    _grace.text = a.lateFeeGraceDays.toString();
    _prefix.text = a.invoicePrefix;
    _latePolicy = a.lateFeePolicy;
  }

  static TimeOfDay? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _fmtDate(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
    });
    try {
      await updateMyAcademy(ref, {
        'name': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'website': _website.text.trim().isEmpty ? null : _website.text.trim(),
        'logo': _logo,
        'sports_offered': _sports,
        'hours_open': _open == null ? null : _fmtTime(_open!),
        'hours_close': _close == null ? null : _fmtTime(_close!),
        'holidays': _holidays.map(_fmtDate).toList(),
        'late_fee_grace_days':
            int.tryParse(_grace.text.trim()) ?? 5,
        'late_fee_policy': _latePolicy,
        'invoice_prefix':
            _prefix.text.trim().isEmpty ? 'INV' : _prefix.text.trim(),
      });
      setState(() => _message = 'Saved');
    } on Object catch (e) {
      setState(() {
        _message = e.toString();
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addSport() {
    final s = _newSport.text.trim();
    if (s.isEmpty) return;
    if (_sports.any((x) => x.toLowerCase() == s.toLowerCase())) {
      _newSport.clear();
      return;
    }
    setState(() {
      _sports = [..._sports, s];
      _newSport.clear();
    });
  }

  Future<void> _pickTime({required bool open}) async {
    final initial = (open ? _open : _close) ??
        const TimeOfDay(hour: 6, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (open) {
          _open = picked;
        } else {
          _close = picked;
        }
      });
    }
  }

  Future<void> _addHoliday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    final iso = _fmtDate(picked);
    if (_holidays.any((d) => _fmtDate(d) == iso)) return;
    setState(() {
      _holidays = [..._holidays, picked]..sort();
    });
  }

  @override
  Widget build(BuildContext context) {
    final academyAsync = ref.watch(myAcademyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Academy settings')),
      body: academyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (academy) {
          if (academy == null) {
            return const Center(child: Text('No academy found.'));
          }
          _hydrate(academy);
          final initials = _name.text.isNotEmpty ? _name.text[0] : 'A';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: AvatarPicker(
                    entity: 'academy',
                    url: _logo,
                    fallbackInitials: initials,
                    onUploaded: (url) => setState(() => _logo = url),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _city,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _website,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Website'),
                ),
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Sports offered'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in _sports)
                      Chip(
                        label: Text(s),
                        onDeleted: () => setState(() {
                          _sports = _sports.where((x) => x != s).toList();
                        }),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newSport,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addSport(),
                        decoration: const InputDecoration(
                          labelText: 'Add a sport',
                          hintText: 'Cricket, Badminton, Swimming…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _addSport,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Operating hours'),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickTime(open: true),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Open'),
                          child: Text(_open == null
                              ? 'Tap to pick'
                              : _fmtTime(_open!)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickTime(open: false),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Close'),
                          child: Text(_close == null
                              ? 'Tap to pick'
                              : _fmtTime(_close!)),
                        ),
                      ),
                    ),
                    if (_open != null || _close != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear hours',
                        onPressed: () => setState(() {
                          _open = null;
                          _close = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Holidays'),
                if (_holidays.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No holidays scheduled.'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final d in _holidays)
                        Chip(
                          label: Text(_fmtDate(d)),
                          onDeleted: () => setState(() {
                            _holidays = _holidays
                                .where((x) => _fmtDate(x) != _fmtDate(d))
                                .toList();
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_outlined),
                  label: const Text('Add holiday'),
                  onPressed: _addHoliday,
                ),
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Billing defaults'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _prefix,
                        decoration: const InputDecoration(
                          labelText: 'Invoice prefix',
                          hintText: 'INV',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _grace,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Grace days',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _latePolicy,
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('No late fee')),
                    DropdownMenuItem(
                        value: 'one_time', child: Text('One-time fee')),
                    DropdownMenuItem(
                        value: 'daily', child: Text('Per-day after grace')),
                  ],
                  onChanged: (v) =>
                      setState(() => _latePolicy = v ?? 'one_time'),
                  decoration: const InputDecoration(
                    labelText: 'Default late-fee policy',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Per-fee overrides on a fee structure win over these defaults.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _isError ? Colors.red : Colors.green,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
