import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/billing/presentation/student_discounts_section.dart';
import 'package:playhub/features/billing/presentation/student_fees_section.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';
import 'package:playhub/features/performance/presentation/performance_history_page.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/features/students/presentation/student_documents_section.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class StudentFormPage extends ConsumerStatefulWidget {
  const StudentFormPage({super.key, this.existing});

  final Student? existing;

  @override
  ConsumerState<StudentFormPage> createState() => _StudentFormPageState();
}

class _StudentFormPageState extends ConsumerState<StudentFormPage> {
  late final _firstName = TextEditingController(
    text: widget.existing?.firstName ?? '',
  );
  late final _lastName = TextEditingController(
    text: widget.existing?.lastName ?? '',
  );
  late final _parentName = TextEditingController(
    text: widget.existing?.parentName ?? '',
  );
  late final _parentPhone = TextEditingController(
    text: widget.existing?.parentPhone ?? '',
  );
  late final _parentEmail = TextEditingController(
    text: widget.existing?.parentEmail ?? '',
  );
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _medical = TextEditingController(
    text: widget.existing?.medicalNotes ?? '',
  );

  String? _gender;
  String? _skillLevel;
  String? _centerId;
  String? _sportId;
  String _status = 'active';
  DateTime? _dob;
  String? _photo;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

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
    // A student must belong to a center. A null-center student is visible and
    // editable by EVERY center_admin (the center_admin_sees_*(null)=true rule),
    // which breaks per-center isolation. The dropdown's validator covers the
    // data state; this backstops loading/error (and the no-centers case).
    if (_centerId == null) {
      AppSnackbar.error(
        context,
        'Pick a center for this student — add one in Settings → Centers first.',
      );
      return;
    }
    setState(() => _busy = true);
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
      if (!mounted) return;
      AppSnackbar.success(
        context,
        isEdit ? 'Student updated.' : 'Student created.',
      );
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  /// Soft-delete: archive the student (status → inactive). Confirmed first
  /// because it's a destructive-feeling action, even though it's reversible.
  Future<void> _confirmArchive() async {
    final ok = await confirmAction(
      context,
      title: 'Archive this student?',
      message:
          'They will be set to Inactive and hidden from active lists. Their '
          'attendance, performance and billing history is kept — you can '
          'reactivate them anytime by changing their status back.',
      confirmLabel: 'Archive',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await archiveStudent(ref, widget.existing!.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Student archived.');
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centresAsync = ref.watch(centersProvider);
    final caps = ref.watch(capabilitiesProvider);
    final theme = Theme.of(context);
    // head_coach / coach own specific sports; show only those in the sport
    // picker so it stays consistent with the batch form. (Student writes are
    // center-scoped — sport_id isn't RLS-gated — so this is for clarity, not
    // error-avoidance.)
    final sportScoped = caps.role == 'head_coach' || caps.role == 'coach';
    final restrictSports = sportScoped
        ? (ref.watch(mySportIdsProvider).valueOrNull ?? const <String>[]).toSet()
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit student' : 'New student')),
      // v1 archetype D: the primary action is pinned to a soft-floating bottom
      // bar so it's always reachable above the long edit-mode form.
      bottomNavigationBar: _SaveBar(
        label: isEdit ? 'Save changes' : 'Create student',
        busy: _busy,
        onPressed: _busy ? null : _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Center(
              child: AvatarPicker(
                entity: 'students',
                url: _photo,
                fallbackInitials: _initials(),
                onUploaded: (url) => setState(() => _photo = url),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // One consistent required-marker legend for the whole form.
            Text(
              'Fields marked * are required.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ----- Student identity --------------------------------------
            const AppSectionHeader(title: 'Student'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _firstName,
                    label: 'First name *',
                    validator: _required,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppFormField(
                    controller: _lastName,
                    label: 'Last name *',
                    validator: _required,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppDateField(
                    label: 'Date of birth',
                    value: _dob,
                    onTap: _pickDob,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppDropdownField<String>(
                    label: 'Gender',
                    value: _gender,
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // ----- Contact (parent + location kept together) -------------
            const AppSectionHeader(title: 'Parent / Contact'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _parentName,
              label: 'Parent name *',
              validator: _required,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _parentPhone,
                    label: 'Parent phone',
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppFormField(
                    controller: _parentEmail,
                    label: 'Parent email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(controller: _city, label: 'City'),
            const SizedBox(height: AppSpacing.xl),

            // ----- Training ----------------------------------------------
            const AppSectionHeader(title: 'Training'),
            const SizedBox(height: AppSpacing.sm),
            centresAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (e, _) => Text(friendlyError(e)),
              data: (centres) => AppDropdownField<String>(
                label: 'Center *',
                value: _centerId,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
                items: [
                  const DropdownMenuItem<String>(
                    child: Text('— select a center —'),
                  ),
                  for (final c in centres.where((c) => c.isActive))
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _centerId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SportPicker(
                    value: _sportId,
                    onChanged: (v) => setState(() => _sportId = v),
                    centerId: _centerId,
                    restrictToSportIds: restrictSports,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppDropdownField<String>(
                    label: 'Skill level',
                    value: _skillLevel,
                    items: const [
                      DropdownMenuItem(
                        value: 'beginner',
                        child: Text('Beginner'),
                      ),
                      DropdownMenuItem(
                        value: 'intermediate',
                        child: Text('Intermediate'),
                      ),
                      DropdownMenuItem(
                        value: 'advanced',
                        child: Text('Advanced'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _skillLevel = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String>(
              label: 'Status',
              value: _status,
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'paused', child: Text('Paused')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                DropdownMenuItem(value: 'graduated', child: Text('Graduated')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ----- Health & notes ----------------------------------------
            const AppSectionHeader(title: 'Health & notes'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _medical,
              label: 'Medical notes',
              hint: 'Allergies, conditions, medications',
              maxLines: 3,
            ),

            // ----- Edit-only record sections (clearly below a divider) ---
            if (isEdit) ...[
              const SizedBox(height: AppSpacing.xxl),
              const Divider(),
              const SizedBox(height: AppSpacing.lg),
              const AppSectionHeader(title: 'Activity'),
              const SizedBox(height: AppSpacing.sm),
              _AttendanceSummaryCard(student: widget.existing!),
              const SizedBox(height: AppSpacing.md),
              _PerformanceShortcut(student: widget.existing!),
              const SizedBox(height: AppSpacing.xl),
              // Finance is only visible to roles with viewRevenue (admin tier +
              // center_admin). head_coach/coach reach this form via manageStudents
              // but can't read finance (can_view_student_finance) — hiding the
              // sections avoids a misleading "nothing assigned" empty state.
              if (ref.watch(capabilitiesProvider).viewRevenue) ...[
                StudentFeesSection(studentId: widget.existing!.id),
                const SizedBox(height: AppSpacing.xl),
                StudentDiscountsSection(studentId: widget.existing!.id),
                const SizedBox(height: AppSpacing.xl),
              ],
              StudentDocumentsSection(studentId: widget.existing!.id),
              const SizedBox(height: AppSpacing.xl),
              const AppSectionHeader(title: 'Logins & access'),
              const SizedBox(height: AppSpacing.sm),
              _ParentAccessCard(student: widget.existing!),
              const SizedBox(height: AppSpacing.md),
              _StudentLoginCard(student: widget.existing!),
              if (caps.manageStudents) ...[
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Danger zone'),
                const SizedBox(height: AppSpacing.sm),
                _ArchiveButton(
                  label: 'Archive student',
                  busy: _busy,
                  onPressed: _confirmArchive,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Pinned bottom action bar for the form (v1 archetype D). A full-width primary
/// [FilledButton] on a white bar lifted with [AppShadows.floating]; the button
/// swaps to an inline spinner while [busy].
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: AppShadows.floating,
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onPressed,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ),
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
      error: (e, _) => Text(friendlyError(e)),
      data: (s) {
        if (s == null || s.totalSessions == 0) {
          return const AppCard(
            padding: EdgeInsets.zero,
            child: AppListTile(
              leading: Icon(Icons.event_available_outlined),
              title: Text('Attendance'),
              subtitle: Text('No sessions in the last 30 days yet.'),
            ),
          );
        }
        return AppCard(
          padding: EdgeInsets.zero,
          child: AppListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              '${s.attendancePct?.toStringAsFixed(0) ?? '—'}% attendance',
            ),
            subtitle: Text(
              '${s.presentCount + s.lateCount}/${s.totalSessions} sessions '
              '(last 30 days)',
            ),
            trailing: s.attendancePct != null && s.attendancePct! < 60
                ? const AppBadge(text: 'Low', tone: AppBadgeTone.warning)
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
    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListTile(
        leading: const Icon(Icons.insights_outlined),
        title: const Text('Performance assessments'),
        subtitle: const Text('View history or record a new assessment'),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => PerformanceHistoryPage(student: student),
          ),
        ),
      ),
    );
  }
}

void _openInvite(BuildContext ctx, InvitePreset preset) {
  showModalBottomSheet<void>(
    context: ctx,
    isScrollControlled: true,
    builder: (_) => InviteUserSheet(preset: preset),
  );
}

/// Full-width destructive outlined button for the form "Danger zone". Tinted
/// with the theme danger color and disabled while [busy], matching the
/// lifecycle-action styling used on the center form.
class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final danger = AppSemanticColors.of(context).danger;
    return OutlinedButton.icon(
      icon: Icon(Icons.archive_outlined, color: danger),
      label: Text(label, style: TextStyle(color: danger)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: danger.withValues(alpha: 0.5)),
      ),
      onPressed: busy ? null : onPressed,
    );
  }
}

/// Parent access — its own labeled row. Reflects an existing link instead of
/// always re-offering the invite.
class _ParentAccessCard extends ConsumerWidget {
  const _ParentAccessCard({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync = ref.watch(studentParentLinksProvider(student.id));
    return AppCard(
      padding: EdgeInsets.zero,
      child: linksAsync.when(
        loading: () => const AppListTile(
          leading: Icon(Icons.family_restroom_outlined),
          title: Text('Invite parent'),
          subtitle: LinearProgressIndicator(),
        ),
        error: (_, __) => _inviteParentTile(context),
        data: (links) => links.isEmpty
            ? _inviteParentTile(context)
            : AppListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Parent linked'),
                subtitle: Text(
                  links
                      .map((l) => '${l.name} (${l.relationship})')
                      .join(', '),
                ),
              ),
      ),
    );
  }

  Widget _inviteParentTile(BuildContext context) => AppListTile(
        leading: const Icon(Icons.family_restroom_outlined),
        title: const Text('Invite parent'),
        subtitle: const Text(
          'Send a magic-link email; they get the parent dashboard '
          'and only see this student.',
        ),
        onTap: () => _openInvite(
          context,
          InvitePreset(
            role: 'parent',
            title: 'Invite parent of ${student.firstName}',
            email: student.parentEmail,
            firstName: student.parentName,
            linkToStudentId: student.id,
            linkRelationship: 'parent',
          ),
        ),
      );
}

/// Student login — its own labeled row. Gated on whether the record already
/// has a login.
class _StudentLoginCard extends StatelessWidget {
  const _StudentLoginCard({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: student.userId != null
          ? const AppListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('Student can log in'),
              subtitle: Text('They already have their own login.'),
            )
          : AppListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Invite student to log in'),
              subtitle: const Text(
                'For older students who manage their own attendance + '
                'performance view.',
              ),
              onTap: () => _openInvite(
                context,
                InvitePreset(
                  role: 'student',
                  title: 'Invite ${student.firstName} to log in',
                  email: student.email,
                  firstName: student.firstName,
                  lastName: student.lastName,
                  linkStudentLoginId: student.id,
                ),
              ),
            ),
    );
  }
}
