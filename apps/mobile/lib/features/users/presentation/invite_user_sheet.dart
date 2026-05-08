import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/users/data/invite_repo.dart';

/// Bottom-sheet form to invite a team member by email.
///
/// Modes:
///   - normal team invite (default) — pick role, optional center.
///   - parent-link mode (preset)    — role=parent, locks studentId.
///   - coach-login mode (preset)    — role=coach, locks coachId.
///   - student-login mode (preset)  — role=student, locks studentId.
class InviteUserSheet extends ConsumerStatefulWidget {
  const InviteUserSheet({
    super.key,
    this.preset,
  });

  final InvitePreset? preset;

  @override
  ConsumerState<InviteUserSheet> createState() => _InviteUserSheetState();
}

class InvitePreset {
  const InvitePreset({
    required this.role,
    required this.title,
    this.linkToStudentId,
    this.linkRelationship,
    this.linkCoachId,
    this.linkStudentLoginId,
  });

  final String role;
  final String title;
  final String? linkToStudentId;
  final String? linkRelationship;
  final String? linkCoachId;
  final String? linkStudentLoginId;
}

class _InviteUserSheetState extends ConsumerState<InviteUserSheet> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  String _role = 'coach';
  String? _centerId;
  bool _busy = false;
  String? _error;

  static const _normalRoles = [
    ('academy_admin', 'Admin'),
    ('center_admin', 'Center admin'),
    ('head_coach', 'Head coach'),
    ('coach', 'Coach'),
    ('trainer', 'Trainer'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.preset != null) _role = widget.preset!.role;
  }

  @override
  void dispose() {
    _email.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(inviteRepoProvider);
      final result = await repo.invite(
        email: _email.text.trim(),
        role: _role,
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        centerId: _centerId,
        linkToStudentId: widget.preset?.linkToStudentId,
        linkRelationship: widget.preset?.linkRelationship,
        linkCoachId: widget.preset?.linkCoachId,
        linkStudentLoginId: widget.preset?.linkStudentLoginId,
      );
      if (mounted) {
        final email = _email.text.trim();
        final msg = result.resent
            ? (result.hasSignedIn
                ? '$email has already signed in once. A fresh invite link '
                    'was sent — they can use it as a magic-link login.'
                : 'Resent invite to $email')
            : 'Invite sent to $email';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(preset?.title ?? 'Invite team member',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'They\'ll get a magic-link email to set their password and '
              'sign in.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email *'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Valid email required' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _first,
                  decoration:
                      const InputDecoration(labelText: 'First name'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _last,
                  decoration:
                      const InputDecoration(labelText: 'Last name'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (preset == null)
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final r in _normalRoles)
                    DropdownMenuItem(value: r.$1, child: Text(r.$2)),
                ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Chip(label: Text('Role: ${_roleLabel(_role)}')),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: Text(_busy ? 'Sending…' : 'Send invite'),
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(String r) =>
      const {
        'academy_admin': 'Admin',
        'center_admin': 'Center admin',
        'head_coach': 'Head coach',
        'coach': 'Coach',
        'trainer': 'Trainer',
        'parent': 'Parent',
        'student': 'Student',
      }[r] ?? r;
}

