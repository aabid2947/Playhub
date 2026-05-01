import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/coaches/presentation/coach_documents_section.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';

class CoachFormPage extends ConsumerStatefulWidget {
  const CoachFormPage({super.key, this.existing});

  final Coach? existing;

  @override
  ConsumerState<CoachFormPage> createState() => _CoachFormPageState();
}

class _CoachFormPageState extends ConsumerState<CoachFormPage> {
  late final _firstName =
      TextEditingController(text: widget.existing?.firstName ?? '');
  late final _lastName =
      TextEditingController(text: widget.existing?.lastName ?? '');
  late final _email =
      TextEditingController(text: widget.existing?.email ?? '');
  late final _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final _specialization = TextEditingController(
      text: widget.existing?.specialization.join(', ') ?? '');
  late final _qualifications = TextEditingController(
      text: widget.existing?.qualifications.join(', ') ?? '');
  late final _certifications = TextEditingController(
      text: widget.existing?.certifications.join(', ') ?? '');
  late final _experience = TextEditingController(
      text: widget.existing?.experienceYears?.toString() ?? '');
  late final _salary = TextEditingController(
      text: widget.existing?.salary?.toStringAsFixed(0) ?? '');

  String? _centerId;
  String? _paymentType;
  String? _photo;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _centerId = widget.existing?.centerId;
    _paymentType = widget.existing?.paymentType;
    _photo = widget.existing?.photo;
  }

  String _initials() {
    final f = _firstName.text.trim();
    final l = _lastName.text.trim();
    return '${f.isEmpty ? '' : f[0]}${l.isEmpty ? '' : l[0]}';
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _specialization.dispose();
    _qualifications.dispose();
    _certifications.dispose();
    _experience.dispose();
    _salary.dispose();
    super.dispose();
  }

  String? _emptyToNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final patch = <String, dynamic>{
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'email': _emptyToNull(_email),
        'phone': _emptyToNull(_phone),
        'specialization': splitCsv(_specialization.text),
        'qualifications': splitCsv(_qualifications.text),
        'certifications': splitCsv(_certifications.text),
        'experience_years': _experience.text.trim().isEmpty
            ? null
            : int.tryParse(_experience.text.trim()),
        'salary': _salary.text.trim().isEmpty
            ? null
            : double.tryParse(_salary.text.trim()),
        'payment_type': _paymentType,
        'center_id': _centerId,
        'photo': _photo,
      };
      if (isEdit) {
        await updateCoach(ref, widget.existing!.id, patch);
      } else {
        await createCoach(ref, patch);
      }
      if (mounted) context.pop();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centresAsync = ref.watch(centersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit coach' : 'New coach')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AvatarPicker(
                  entity: 'coaches',
                  url: _photo,
                  fallbackInitials: _initials(),
                  onUploaded: (url) => setState(() => _photo = url),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Personal'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstName,
                      decoration:
                          const InputDecoration(labelText: 'First name *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastName,
                      decoration:
                          const InputDecoration(labelText: 'Last name *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Expertise'),
              TextFormField(
                controller: _specialization,
                decoration: const InputDecoration(
                  labelText: 'Specialization',
                  hintText: 'Cricket, Batting, Fielding (comma-separated)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _experience,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Experience (yrs)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: centresAsync.when(
                      loading: () =>
                          const LinearProgressIndicator(minHeight: 2),
                      error: (e, _) => Text('Centres error: $e'),
                      data: (centres) => DropdownButtonFormField<String>(
                        initialValue: _centerId,
                        decoration: const InputDecoration(labelText: 'Center'),
                        items: [
                          const DropdownMenuItem<String>(
                              child: Text('— none —')),
                          for (final c in centres.where((c) => c.isActive))
                            DropdownMenuItem(
                                value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => setState(() => _centerId = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _qualifications,
                decoration: const InputDecoration(
                  labelText: 'Qualifications',
                  hintText: 'BPEd, MPEd (comma-separated)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _certifications,
                decoration: const InputDecoration(
                  labelText: 'Certifications',
                  hintText: 'NIS Level 1, ICC Coaching Certificate',
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Compensation'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _salary,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Salary (₹)',
                        prefixText: '₹ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentType,
                      decoration:
                          const InputDecoration(labelText: 'Payment type'),
                      items: const [
                        DropdownMenuItem(
                            value: 'monthly', child: Text('Monthly')),
                        DropdownMenuItem(
                            value: 'hourly', child: Text('Hourly')),
                        DropdownMenuItem(
                            value: 'session', child: Text('Per session')),
                      ],
                      onChanged: (v) => setState(() => _paymentType = v),
                    ),
                  ),
                ],
              ),
              if (isEdit) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                CoachDocumentsSection(coachId: widget.existing!.id),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
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
                    : Text(isEdit ? 'Save changes' : 'Create coach'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
