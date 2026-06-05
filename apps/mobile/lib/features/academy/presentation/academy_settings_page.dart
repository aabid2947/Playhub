import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/academy/data/academy.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
  final _prefix = TextEditingController();
  bool _busy = false;
  Academy? _loaded;
  String? _logo;
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
    _open = _parseTime(a.hoursOpen);
    _close = _parseTime(a.hoursClose);
    _holidays = List.of(a.holidays);
    _prefix.text = a.invoicePrefix;
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
    setState(() => _busy = true);
    try {
      await updateMyAcademy(ref, {
        'name': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'website': _website.text.trim().isEmpty ? null : _website.text.trim(),
        'logo': _logo,
        'hours_open': _open == null ? null : _fmtTime(_open!),
        'hours_close': _close == null ? null : _fmtTime(_close!),
        'holidays': _holidays.map(_fmtDate).toList(),
        'invoice_prefix':
            _prefix.text.trim().isEmpty ? 'INV' : _prefix.text.trim(),
      });
      if (mounted) AppSnackbar.success(context, 'Saved.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(myAcademyProvider),
        ),
        data: (academy) {
          if (academy == null) {
            return const AppEmptyState(
              icon: Icons.business_outlined,
              title: 'No academy found',
            );
          }
          _hydrate(academy);
          final initials = _name.text.isNotEmpty ? _name.text[0] : 'A';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
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
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Profile'),
                const SizedBox(height: AppSpacing.sm),
                AppFormField(controller: _name, label: 'Name'),
                const SizedBox(height: AppSpacing.md),
                AppFormField(
                  controller: _email,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppSpacing.md),
                AppFormField(
                  controller: _phone,
                  label: 'Phone',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: AppSpacing.md),
                AppFormField(
                  controller: _address,
                  label: 'Address',
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.md),
                AppFormField(controller: _city, label: 'City'),
                const SizedBox(height: AppSpacing.md),
                AppFormField(
                  controller: _website,
                  label: 'Website',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Operating hours'),
                const SizedBox(height: AppSpacing.sm),
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
                    const SizedBox(width: AppSpacing.md),
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
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Holidays'),
                const SizedBox(height: AppSpacing.sm),
                if (_holidays.isEmpty)
                  Text(
                    'No holidays scheduled.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
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
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_outlined),
                  label: const Text('Add holiday'),
                  onPressed: _addHoliday,
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Invoicing'),
                const SizedBox(height: AppSpacing.sm),
                AppFormField(
                  controller: _prefix,
                  label: 'Invoice prefix',
                  hint: 'INV',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Late-fee policy is set per fee structure, not here.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.xl),
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
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          );
        },
      ),
    );
  }
}
