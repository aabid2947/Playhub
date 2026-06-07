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

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Close must be strictly after open when both are set.
  bool get _hoursValid =>
      _open == null || _close == null || _minutes(_close!) > _minutes(_open!);

  Future<void> _save() async {
    if (!_hoursValid) {
      AppSnackbar.error(context, 'Closing time must be after opening time.');
      return;
    }
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
    final initial =
        (open ? _open : _close) ?? const TimeOfDay(hour: 6, minute: 0);
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

  void _removeHoliday(DateTime d) {
    setState(() {
      _holidays =
          _holidays.where((x) => _fmtDate(x) != _fmtDate(d)).toList();
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
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _ProfileSection(
                logo: _logo,
                initials: initials,
                onLogoUploaded: (url) => setState(() => _logo = url),
                name: _name,
                email: _email,
                phone: _phone,
                address: _address,
                city: _city,
                website: _website,
              ),
              const SizedBox(height: AppSpacing.xl),
              _HoursSection(
                open: _open,
                close: _close,
                valid: _hoursValid,
                onPickOpen: () => _pickTime(open: true),
                onPickClose: () => _pickTime(open: false),
                onClear: () => setState(() {
                  _open = null;
                  _close = null;
                }),
              ),
              const SizedBox(height: AppSpacing.xl),
              _HolidaysSection(
                holidays: _holidays,
                onAdd: _addHoliday,
                onRemove: _removeHoliday,
              ),
              const SizedBox(height: AppSpacing.xl),
              _InvoicingSection(
                prefix: _prefix,
                onChanged: (_) => setState(() {}),
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
          );
        },
      ),
    );
  }
}

/// Logo + the academy's identity/contact details, grouped into one card.
class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.logo,
    required this.initials,
    required this.onLogoUploaded,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.website,
  });

  final String? logo;
  final String initials;
  final ValueChanged<String> onLogoUploaded;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController address;
  final TextEditingController city;
  final TextEditingController website;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(title: 'Profile'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AvatarPicker(
                  entity: 'academy',
                  url: logo,
                  fallbackInitials: initials,
                  onUploaded: onLogoUploaded,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppFormField(controller: name, label: 'Name'),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: phone,
                label: 'Phone',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: address,
                label: 'Address',
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(controller: city, label: 'City'),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: website,
                label: 'Website',
                keyboardType: TextInputType.url,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Open/close hours as two consistent label-above fields, with an inline
/// close-after-open validation cue and a clear affordance.
class _HoursSection extends StatelessWidget {
  const _HoursSection({
    required this.open,
    required this.close,
    required this.valid,
    required this.onPickOpen,
    required this.onPickClose,
    required this.onClear,
  });

  final TimeOfDay? open;
  final TimeOfDay? close;
  final bool valid;
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;
  final VoidCallback onClear;

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final hasAny = open != null || close != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Operating hours',
          trailing: hasAny
              ? TextButton(
                  onPressed: onClear,
                  child: const Text('Clear'),
                )
              : null,
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'Opens',
                      value: open,
                      onTap: onPickOpen,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _TimeField(
                      label: 'Closes',
                      value: close,
                      onTap: onPickClose,
                    ),
                  ),
                ],
              ),
              if (!valid) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: semantic.danger,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Closing time must be after opening time.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: semantic.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (open != null && close != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Open ${_fmt(open!)}–${_fmt(close!)} daily.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A tappable time field mirroring [AppDateField]'s label-above layout, so the
/// hours read consistently with the rest of the form's inputs.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
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
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InputDecorator(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.schedule_outlined),
            ),
            child: Text(
              v == null ? 'Tap to pick' : v.format(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Holiday list as a tidy chip block with a single add affordance.
class _HolidaysSection extends StatelessWidget {
  const _HolidaysSection({
    required this.holidays,
    required this.onAdd,
    required this.onRemove,
  });

  final List<DateTime> holidays;
  final VoidCallback onAdd;
  final ValueChanged<DateTime> onRemove;

  static String _fmt(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Holidays',
          trailing: holidays.isEmpty
              ? null
              : Text(
                  '${holidays.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (holidays.isEmpty)
                Text(
                  'No holidays scheduled. Closed days are excluded from '
                  'session scheduling.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final d in holidays)
                      Chip(
                        label: Text(_fmt(d)),
                        onDeleted: () => onRemove(d),
                        deleteButtonTooltipMessage: 'Remove holiday',
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_outlined),
                  label: const Text('Add holiday'),
                  onPressed: onAdd,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Invoice prefix plus a live example of the resulting invoice number.
class _InvoicingSection extends StatelessWidget {
  const _InvoicingSection({
    required this.prefix,
    required this.onChanged,
  });

  final TextEditingController prefix;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective =
        prefix.text.trim().isEmpty ? 'INV' : prefix.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(title: 'Invoicing'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppFormField(
                controller: prefix,
                label: 'Invoice prefix',
                hint: 'INV',
                onChanged: onChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          children: [
                            const TextSpan(text: 'Example: '),
                            TextSpan(
                              text: '$effective-000001',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: AppType.semibold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Late-fee policy is set per fee structure, not here.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
