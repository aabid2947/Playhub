import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class LeadFormPage extends ConsumerStatefulWidget {
  const LeadFormPage({super.key});

  @override
  ConsumerState<LeadFormPage> createState() => _LeadFormPageState();
}

class _LeadFormPageState extends ConsumerState<LeadFormPage> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _parentName = TextEditingController();
  final _notes = TextEditingController();
  final _age = TextEditingController();
  String? _sportId;
  LeadSource _source = LeadSource.walkIn;
  bool _saving = false;
  // Once the user has tried to submit, validate as they type so the
  // phone-OR-email cross-field rule clears the moment a contact is filled.
  bool _autoValidate = false;

  @override
  void dispose() {
    for (final c in [
      _first,
      _last,
      _email,
      _phone,
      _parentName,
      _notes,
      _age,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Phone-OR-email: at least one contact channel is required. Surfaced inline
  // on both fields so the lead is reachable; re-runs live after first submit.
  String? _contactValidator(String? _) {
    if (_phone.text.trim().isEmpty && _email.text.trim().isEmpty) {
      return 'Add a phone number or email';
    }
    return null;
  }

  void _revalidateContact() {
    if (_autoValidate) _form.currentState?.validate();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      setState(() => _autoValidate = true);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = await ref.read(leadsRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.create(
        firstName: _first.text.trim(),
        lastName: _last.text.trim().isEmpty ? null : _last.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        parentName:
            _parentName.text.trim().isEmpty ? null : _parentName.text.trim(),
        age: int.tryParse(_age.text.trim()),
        sportId: _sportId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        source: _source,
      );
      ref.invalidate(leadsListProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Lead created.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New lead')),
      body: Form(
        key: _form,
        autovalidateMode: _autoValidate
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // ── Contact ──────────────────────────────────────────────
            const AppSectionHeader(
              title: 'Contact',
              icon: Icons.contact_phone_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            // First + last sit side-by-side on wide layouts and stack to full
            // width when the screen is too narrow to hold both usably.
            _NameRow(
              first: AppFormField(
                controller: _first,
                label: 'First name *',
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              last: AppFormField(
                controller: _last,
                label: 'Last name',
                enabled: !_saving,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _phone,
              label: 'Phone',
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              prefixIcon: const Icon(Icons.call_outlined),
              onChanged: (_) => _revalidateContact(),
              validator: _contactValidator,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _email,
              label: 'Email',
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: const Icon(Icons.mail_outline),
              onChanged: (_) => _revalidateContact(),
              validator: _contactValidator,
            ),
            const SizedBox(height: AppSpacing.sm),
            // Cross-field hint for the phone-OR-email rule — a quiet info row
            // so the requirement is clear before the inline validator fires.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'A phone number or email is required so the lead is '
                    'reachable.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            // ── Interest & source ────────────────────────────────────
            const AppSectionHeader(
              title: 'Interest & source',
              icon: Icons.sports_rounded,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _parentName,
              label: 'Parent name',
              enabled: !_saving,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _age,
              label: 'Age',
              enabled: !_saving,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            SportPicker(
              value: _sportId,
              onChanged: (v) => setState(() => _sportId = v),
              label: 'Sport interest',
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<LeadSource>(
              label: 'Source',
              value: _source,
              items: [
                for (final s in LeadSource.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged:
                  _saving ? null : (v) => setState(() => _source = v ?? _source),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _notes,
              label: 'Notes',
              enabled: !_saving,
              maxLines: 3,
            ),
          ],
        ),
      ),
      // Pinned, full-width primary action — inline spinner while saving. A
      // floating shadow lifts the bar off the scrolling form below it.
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
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Saving…' : 'Save lead'),
              onPressed: _saving ? null : _save,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays first/last name out side-by-side on wide layouts and stacks them to
/// full width when the screen is too narrow to hold both inputs usably.
class _NameRow extends StatelessWidget {
  const _NameRow({required this.first, required this.last});

  final Widget first;
  final Widget last;

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
              first,
              const SizedBox(height: AppSpacing.md),
              last,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: last),
          ],
        );
      },
    );
  }
}
