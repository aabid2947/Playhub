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

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
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
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const AppSectionHeader(title: 'Contact'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _first,
              label: 'First name *',
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _last,
              label: 'Last name',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _phone,
              label: 'Phone',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              validator: (_) {
                if (_phone.text.trim().isEmpty &&
                    _email.text.trim().isEmpty) {
                  return 'Phone or email required';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Interest & source'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _parentName,
              label: 'Parent name',
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _age,
              label: 'Age',
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
              onChanged: (v) => setState(() => _source = v ?? _source),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _notes,
              label: 'Notes',
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving…' : 'Save lead'),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
