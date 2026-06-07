import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/users/data/invite_repo.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Bottom-sheet form to invite a team member by email.
///
/// Modes:
///   - normal team invite (default) — pick role, optional center.
///   - parent-link mode (preset)    — role=parent, locks studentId.
///   - coach-login mode (preset)    — role=coach, locks coachId.
///   - student-login mode (preset)  — role=student, locks studentId.
class InviteUserSheet extends ConsumerStatefulWidget {
  const InviteUserSheet({super.key, this.preset});

  final InvitePreset? preset;

  @override
  ConsumerState<InviteUserSheet> createState() => _InviteUserSheetState();
}

class InvitePreset {
  const InvitePreset({
    required this.role,
    required this.title,
    this.email,
    this.firstName,
    this.lastName,
    this.linkToStudentId,
    this.linkRelationship,
    this.linkCoachId,
    this.linkStudentLoginId,
  });

  final String role;
  final String title;
  // Pre-fill values pulled from the source record (coach/student/parent),
  // so the admin doesn't re-type details the app already holds.
  final String? email;
  final String? firstName;
  final String? lastName;
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
    final p = widget.preset;
    if (p != null) {
      _role = p.role;
      if (p.email != null) _email.text = p.email!;
      if (p.firstName != null) _first.text = p.firstName!;
      if (p.lastName != null) _last.text = p.lastName!;
    }
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
    if (widget.preset == null && _role == 'center_admin' && _centerId == null) {
      AppSnackbar.error(context, 'Pick a center for the center admin.');
      return;
    }
    setState(() => _busy = true);
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
      if (!mounted) return;
      final email = _email.text.trim();
      final msg = result.resent
          ? (result.hasSignedIn
                ? '$email has already signed in once. A fresh invite link '
                      'was sent — they can use it as a magic-link login.'
                : 'Resent invite to $email')
          : 'Invite sent to $email';
      AppSnackbar.success(context, msg);
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        // Scrollable + height-bounded so a tall (center field + keyboard)
        // layout never clips behind the keyboard.
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: AppSpacing.xl,
                    height: AppSpacing.xs,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  preset?.title ?? 'Invite team member',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "They'll get a magic-link email to set their password and "
                  'sign in.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // In preset mode the role is locked, so surface it as a clear
                // labeled "Assigned role" row (badge, not a tiny inline label)
                // before the editable fields.
                if (preset != null) ...[
                  _AssignedRoleRow(label: _roleLabel(_role)),
                  const SizedBox(height: AppSpacing.lg),
                ],
                AppFormField(
                  controller: _email,
                  label: 'Email *',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Valid email required'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppFormField(
                        controller: _first,
                        label: 'First name',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppFormField(controller: _last, label: 'Last name'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Normal mode: the admin picks the role; preset mode locks it
                // (shown above), so no picker.
                if (preset == null)
                  AppDropdownField<String>(
                    label: 'Role',
                    value: _role,
                    items: [
                      for (final r in _normalRoles)
                        DropdownMenuItem(value: r.$1, child: Text(r.$2)),
                    ],
                    onChanged: (v) => setState(() {
                      _role = v ?? _role;
                      if (_role != 'center_admin') _centerId = null;
                    }),
                  ),
                // A center admin must be scoped to a center — otherwise the
                // center-narrowed RLS leaves them seeing nothing. Required.
                if (preset == null && _role == 'center_admin') ...[
                  const SizedBox(height: AppSpacing.md),
                  ref
                      .watch(centersProvider)
                      .when(
                        loading: () =>
                            const LinearProgressIndicator(minHeight: 2),
                        error: (e, _) => Text(
                          friendlyError(e),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppSemanticColors.of(context).danger,
                          ),
                        ),
                        data: (centres) {
                          final active = centres
                              .where((c) => c.isActive)
                              .toList();
                          if (active.isEmpty) {
                            return Text(
                              'Create a center first — a center admin must be '
                              'assigned to one.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppSemanticColors.of(context).danger,
                              ),
                            );
                          }
                          return AppDropdownField<String>(
                            label: 'Center *',
                            value: _centerId,
                            items: [
                              for (final c in active)
                                DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                            ],
                            onChanged: (v) => setState(() => _centerId = v),
                          );
                        },
                      ),
                ],
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  icon: _busy
                      ? const SizedBox(
                          width: AppSpacing.md,
                          height: AppSpacing.md,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_busy ? 'Sending…' : 'Send invite'),
                  onPressed: _busy ? null : _submit,
                ),
              ],
            ),
          ),
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
      }[r] ??
      r;
}

/// Labeled, read-only row that makes the locked invite role obvious in preset
/// mode — a small overline plus a prominent brand [AppBadge] (vs. a tiny
/// inline label the admin could miss).
class _AssignedRoleRow extends StatelessWidget {
  const _AssignedRoleRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assigned role',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: AppType.semibold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: AppBadge(text: label, tone: AppBadgeTone.brand),
        ),
      ],
    );
  }
}
