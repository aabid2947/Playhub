import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/billing/presentation/student_discounts_section.dart';
import 'package:playhub/features/billing/presentation/student_fees_section.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/performance/presentation/performance_history_page.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/features/students/presentation/student_documents_section.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';

class StudentFormPage extends ConsumerStatefulWidget {
  const StudentFormPage({super.key, this.existing});

  final Student? existing;

  @override
  ConsumerState<StudentFormPage> createState() => _StudentFormPageState();
}

class _StudentFormPageState extends ConsumerState<StudentFormPage> {
  late final _firstName =
      TextEditingController(text: widget.existing?.firstName ?? '');
  late final _lastName =
      TextEditingController(text: widget.existing?.lastName ?? '');
  late final _parentName =
      TextEditingController(text: widget.existing?.parentName ?? '');
  late final _parentPhone =
      TextEditingController(text: widget.existing?.parentPhone ?? '');
  late final _parentEmail =
      TextEditingController(text: widget.existing?.parentEmail ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _medical =
      TextEditingController(text: widget.existing?.medicalNotes ?? '');

  String? _gender;
  String? _skillLevel;
  String? _centerId;
  String? _sportId;
  String _status = 'active';
  DateTime? _dob;
  String? _photo;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _gender = widget.existing?.gender;
    _skillLevel = widget.existing?.skillLevel;
    _centerId = widget.existing?.centerId;
    _sportId = widget.existing?.sportId;
    _status = widget.existing?.status ?? 'active';
    _dob = widget.existing?.dateOfBirth;
    _photo = widget.existing?.photo;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _parentName.dispose();
    _parentPhone.dispose();
    _parentEmail.dispose();
    _city.dispose();
    _medical.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 12),
      firstDate: DateTime(now.year - 60),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  String? _emptyToNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  String _initials() {
    final f = _firstName.text.trim();
    final l = _lastName.text.trim();
    return '${f.isEmpty ? '' : f[0]}${l.isEmpty ? '' : l[0]}';
  }

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
        'parent_name': _parentName.text.trim(),
        'parent_phone': _emptyToNull(_parentPhone),
        'parent_email': _emptyToNull(_parentEmail),
        'sport_id': _sportId,
        'city': _emptyToNull(_city),
        'medical_notes': _emptyToNull(_medical),
        'gender': _gender,
        'skill_level': _skillLevel,
        'center_id': _centerId,
        'status': _status,
        'date_of_birth': _dob?.toIso8601String().substring(0, 10),
        'photo': _photo,
      };
      if (isEdit) {
        await updateStudent(ref, widget.existing!.id, patch);
      } else {
        await createStudent(ref, patch);
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
      appBar: AppBar(title: Text(isEdit ? 'Edit student' : 'New student')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AvatarPicker(
                  entity: 'students',
                  url: _photo,
                  fallbackInitials: _initials(),
                  onUploaded: (url) => setState(() => _photo = url),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Student'),
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
                    child: InkWell(
                      onTap: _pickDob,
                      child: InputDecorator(
                        decoration:
                            const InputDecoration(labelText: 'Date of birth'),
                        child: Text(
                          _dob == null
                              ? 'Tap to pick'
                              : _dob!.toIso8601String().substring(0, 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('Male')),
                        DropdownMenuItem(
                            value: 'female', child: Text('Female')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) => setState(() => _gender = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Parent / Guardian'),
              TextFormField(
                controller: _parentName,
                decoration: const InputDecoration(labelText: 'Parent name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _parentPhone,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Parent phone'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _parentEmail,
                      keyboardType: TextInputType.emailAddress,
                      decoration:
                          const InputDecoration(labelText: 'Parent email'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Training'),
              centresAsync.when(
                loading: () =>
                    const LinearProgressIndicator(minHeight: 2),
                error: (e, _) => Text('Centres error: $e'),
                data: (centres) => DropdownButtonFormField<String>(
                  initialValue: _centerId,
                  decoration: const InputDecoration(labelText: 'Center'),
                  items: [
                    const DropdownMenuItem<String>(child: Text('— none —')),
                    for (final c in centres.where((c) => c.isActive))
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _centerId = v),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SportPicker(
                      value: _sportId,
                      onChanged: (v) => setState(() => _sportId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _skillLevel,
                      decoration:
                          const InputDecoration(labelText: 'Skill level'),
                      items: const [
                        DropdownMenuItem(
                            value: 'beginner', child: Text('Beginner')),
                        DropdownMenuItem(
                            value: 'intermediate',
                            child: Text('Intermediate')),
                        DropdownMenuItem(
                            value: 'advanced', child: Text('Advanced')),
                      ],
                      onChanged: (v) => setState(() => _skillLevel = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'paused', child: Text('Paused')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  DropdownMenuItem(
                      value: 'graduated', child: Text('Graduated')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'active'),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Other'),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'City'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _medical,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Medical notes',
                  hintText: 'Allergies, conditions, medications',
                ),
              ),
              if (isEdit) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _AttendanceSummaryCard(student: widget.existing!),
                const SizedBox(height: 12),
                _PerformanceShortcut(student: widget.existing!),
                const SizedBox(height: 24),
                StudentFeesSection(studentId: widget.existing!.id),
                const SizedBox(height: 24),
                StudentDiscountsSection(studentId: widget.existing!.id),
                const SizedBox(height: 24),
                StudentDocumentsSection(studentId: widget.existing!.id),
                const SizedBox(height: 24),
                _SectionLabel('Logins & access'),
                _InviteAccessRow(student: widget.existing!),
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
                    : Text(isEdit ? 'Save changes' : 'Create student'),
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

class _AttendanceSummaryCard extends ConsumerWidget {
  const _AttendanceSummaryCard({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(attendanceSummaryProvider(student.id));
    return summaryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Error: $e'),
      data: (s) {
        if (s == null || s.totalSessions == 0) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.event_available_outlined),
              title: Text('Attendance'),
              subtitle: Text(
                'No sessions in the last 30 days yet.',
              ),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              '${s.attendancePct?.toStringAsFixed(0) ?? '—'}% attendance',
            ),
            subtitle: Text(
              '${s.presentCount + s.lateCount}/${s.totalSessions} sessions '
              '(last 30 days)',
            ),
            trailing: s.attendancePct != null && s.attendancePct! < 60
                ? const Icon(Icons.warning_amber_outlined,
                    color: Colors.orange)
                : null,
          ),
        );
      },
    );
  }
}

class _PerformanceShortcut extends StatelessWidget {
  const _PerformanceShortcut({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.insights_outlined),
        title: const Text('Performance assessments'),
        subtitle: const Text('View history or record a new assessment'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => PerformanceHistoryPage(student: student),
          ),
        ),
      ),
    );
  }
}

class _InviteAccessRow extends StatelessWidget {
  const _InviteAccessRow({required this.student});
  final Student student;

  void _open(BuildContext ctx, InvitePreset preset) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => InviteUserSheet(preset: preset),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.family_restroom_outlined),
            title: const Text('Invite parent'),
            subtitle: const Text(
                'Send a magic-link email; they get the parent dashboard '
                'and only see this student.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(
              context,
              InvitePreset(
                role: 'parent',
                title: 'Invite parent of ${student.firstName}',
                linkToStudentId: student.id,
                linkRelationship: 'parent',
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Invite student to log in'),
            subtitle: const Text(
                'For older students who manage their own attendance + '
                'performance view.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(
              context,
              InvitePreset(
                role: 'student',
                title: 'Invite ${student.firstName} to log in',
                linkStudentLoginId: student.id,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
