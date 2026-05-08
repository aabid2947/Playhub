import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';

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
  final _sport = TextEditingController();
  final _notes = TextEditingController();
  final _age = TextEditingController();
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
      _sport,
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
        sport: _sport.text.trim().isEmpty ? null : _sport.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        source: _source,
      );
      ref.invalidate(leadsListProvider);
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
    return Scaffold(
      appBar: AppBar(title: const Text('New lead')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _first,
              decoration: const InputDecoration(labelText: 'First name *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _last,
              decoration: const InputDecoration(labelText: 'Last name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (_) {
                if (_phone.text.trim().isEmpty &&
                    _email.text.trim().isEmpty) {
                  return 'Phone or email required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _parentName,
              decoration: const InputDecoration(labelText: 'Parent name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _age,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Age'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sport,
              decoration: const InputDecoration(labelText: 'Sport interest'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<LeadSource>(
              initialValue: _source,
              decoration: const InputDecoration(labelText: 'Source'),
              items: [
                for (final s in LeadSource.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _source = v ?? _source),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 24),
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
