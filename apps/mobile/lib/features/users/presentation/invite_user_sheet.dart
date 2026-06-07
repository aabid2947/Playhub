import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
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

  // Center-scoped staff roles: when an ADMIN-tier inviter picks one of these,
  // surface the center picker so the new staffer lands in a center (else they're
  // academy-wide). center-scoped inviters never see it — the invite-user fn
  // forces their own center.
  static const _centerScopedTargets = {
    'center_admin', 'head_coach', 'coach', 'trainer',
  };

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
    final caps = ref.read(capabilitiesProvider);
    if (widget.preset == null &&
        !caps.inviteScopedToOwnCenter &&
        _role == 'center_admin' &&
        _centerId == null) {
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
    // Role options mirror the DB provisioning ladder (capabilities.invitableRoles
    // → can_provision_role). Capabilities load with the profile, so the default
    // _role may not be invitable for this user — clamp it to a valid option so
    // the dropdown's value is always one of its items.
    final caps = ref.watch(capabilitiesProvider);
    final roleOptions = caps.invitableRoles;
    if (preset == null &&
        roleOptions.isNotEmpty &&
        !roleOptions.contains(_role)) {
      _role = roleOptions.first;
    }
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
                      for (final r in roleOptions)
                        DropdownMenuItem(value: r, child: Text(_roleLabel(r))),
                    ],
                    onChanged: (v) => setState(() {
                      _role = v ?? _role;
                      if (!_centerScopedTargets.contains(_role)) {
                        _centerId = null;
                      }
                    }),
                  ),
                // Center-scoped staff need a center. Admin-tier inviters pick it
                // here (required for center_admin, optional for head_coach/coach/
                // trainer). center-scoped inviters never see this — the
                // invite-user fn forces their own center.
                if (preset == null &&
                    !caps.inviteScopedToOwnCenter &&
                    _centerScopedTargets.contains(_role)) ...[
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
                              _role == 'center_admin'
                                  ? 'Create a center first — a center admin must '
                                      'be assigned to one.'
                                  : 'No centers yet. This staffer will be '
                                      'academy-wide until you assign a center.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppSemanticColors.of(context).danger,
                              ),
                            );
                          }
                          return AppDropdownField<String>(
                            label:
                                _role == 'center_admin' ? 'Center *' : 'Center',
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
