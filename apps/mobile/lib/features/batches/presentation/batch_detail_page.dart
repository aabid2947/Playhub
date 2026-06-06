import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/attendance/presentation/attendance_marking_page.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/batch_form_page.dart';
import 'package:playhub/features/billing/presentation/batch_discounts_section.dart';
import 'package:playhub/features/billing/presentation/batch_fees_section.dart';
import 'package:playhub/features/chat/presentation/batch_chat_button.dart';
import 'package:playhub/features/chat/presentation/message_parent_button.dart';
import 'package:playhub/features/coach/presentation/coach_student_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class BatchDetailPage extends ConsumerWidget {
  const BatchDetailPage({required this.batch, super.key});

  final Batch batch;

  bool _atCapacity() {
    final cap = batch.capacity;
    if (cap == null) return false;
    return batch.enrolledCount >= cap;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollmentsAsync = ref.watch(batchEnrollmentsProvider(batch.id));
    final studentsAsync = ref.watch(studentsProvider);
    final caps = ref.watch(capabilitiesProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final role = profile?.role;
    // center_admin & head_coach are center-scoped writers (can_manage_batches /
    // can_mark_attendance gate on batch_in_my_center) but can *see* the whole
    // academy. Hide write controls for a batch outside their center rather than
    // letting the action fail under RLS. Admins are academy-wide; coach/trainer
    // only ever reach their own batches, so they're unaffected.
    final isCenterScoped = role == 'center_admin' || role == 'head_coach';
    final inMyCenter =
        batch.centerId == null || batch.centerId == profile?.centerId;
    final scopeOk = !isCenterScoped || inMyCenter;
    final canManageEnroll = caps.manageBatches && scopeOk;
    final canMarkAttendance = caps.markAttendance && scopeOk;
    // Fees/discounts are finance: admin-only write, center_admin view-only.
    final canManageFinance = caps.manageFinance;
    final canViewFinance = caps.viewRevenue;

    return Scaffold(
      appBar: AppBar(
        title: Text(batch.name),
        actions: [
          BatchChatButton(batchId: batch.id, compact: true),
          if (canMarkAttendance)
            IconButton(
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: 'Mark attendance',
              onPressed: () {
                final today = DateTime.now();
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AttendanceMarkingPage(
                      batch: batch,
                      date: DateTime(today.year, today.month, today.day),
                    ),
                  ),
                );
              },
            ),
          if (canManageEnroll)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit batch',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => BatchFormPage(existing: batch),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _HeaderCard(batch: batch, atCapacity: _atCapacity()),
          const SizedBox(height: AppSpacing.lg),
          if (canViewFinance) ...[
            BatchFeesSection(batchId: batch.id, canManage: canManageFinance),
            const SizedBox(height: AppSpacing.lg),
            BatchDiscountsSection(
              batchId: batch.id,
              canManage: canManageFinance,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppSectionHeader(
            title: 'Enrolment',
            trailing: canManageEnroll
                ? _EnrollAction(
                    atCapacity: _atCapacity(),
                    onPressed: () async {
                      final students = studentsAsync.valueOrNull ?? const [];
                      final enrolled = enrollmentsAsync.valueOrNull ?? const [];
                      final activeIds = enrolled
                          .where((e) => e.status != 'withdrawn')
                          .map((e) => e.studentId)
                          .toSet();
                      final candidates = students
                          .where((s) => !activeIds.contains(s.id))
                          .toList();
                      await _showEnrollSheet(
                        context,
                        ref,
                        candidates,
                        waitlist: _atCapacity(),
                      );
                    },
                  )
                : null,
          ),
          enrollmentsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: AppLoading(),
            ),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () =>
                  ref.invalidate(batchEnrollmentsProvider(batch.id)),
            ),
            data: (enrollments) {
              if (enrollments.isEmpty) {
                return AppEmptyState(
                  icon: Icons.group_outlined,
                  title: 'No students enrolled yet',
                  subtitle: canManageEnroll
                      ? 'Use Enrol to add the first student to this batch.'
                      : 'Students enrolled in this batch will appear here.',
                );
              }
              final byId = {
                for (final s
                    in (studentsAsync.valueOrNull ?? const <Student>[]))
                  s.id: s,
              };
              final active =
                  enrollments.where((e) => e.status == 'active').toList();
              final waitlisted = enrollments
                  .where((e) => e.status == 'waitlisted')
                  .toList();
              final withdrawn = enrollments
                  .where((e) => e.status == 'withdrawn')
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (active.isNotEmpty)
                    _EnrollmentSection(
                      title: 'Active',
                      tone: AppBadgeTone.success,
                      enrollments: active,
                      byStudent: byId,
                      onWithdraw: canManageEnroll
                          ? (e) async {
                              await withdrawEnrollment(
                                ref,
                                enrollmentId: e.id,
                                batchId: batch.id,
                              );
                            }
                          : null,
                      onTransfer: canManageEnroll
                          ? (e) => _showTransferSheet(context, ref, e)
                          : null,
                    ),
                  if (waitlisted.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _EnrollmentSection(
                      title: 'Waitlist',
                      tone: AppBadgeTone.warning,
                      enrollments: waitlisted,
                      byStudent: byId,
                      onWithdraw: canManageEnroll
                          ? (e) async {
                              await withdrawEnrollment(
                                ref,
                                enrollmentId: e.id,
                                batchId: batch.id,
                              );
                            }
                          : null,
                      onPromote: (!canManageEnroll || _atCapacity())
                          ? null
                          : (e) async {
                              await promoteEnrollment(
                                ref,
                                enrollmentId: e.id,
                                batchId: batch.id,
                              );
                            },
                    ),
                  ],
                  if (withdrawn.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _EnrollmentSection(
                      title: 'Withdrawn',
                      tone: AppBadgeTone.neutral,
                      enrollments: withdrawn,
                      byStudent: byId,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showTransferSheet(
    BuildContext context,
    WidgetRef ref,
    Enrollment enrollment,
  ) async {
    final batches = ref.read(batchesProvider).valueOrNull ?? const <Batch>[];
    final targets = batches.where((b) => b.id != batch.id).toList();
    if (targets.isEmpty) {
      AppSnackbar.info(context, 'No other batches to transfer to.');
      return;
    }
    final picked = await showModalBottomSheet<Batch>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SheetScaffold(
        title: 'Transfer to which batch?',
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: targets.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final b = targets[i];
            final cap = b.capacity;
            final atCap = cap != null && b.enrolledCount >= cap;
            return AppListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(b.name),
              subtitle: Text(
                atCap
                    ? '${b.schedule.summary} • at capacity (will go on waitlist)'
                    : b.schedule.summary,
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => Navigator.of(ctx).pop(b),
            );
          },
        ),
      ),
    );
    if (picked == null) return;
    try {
      await transferEnrollment(
        ref,
        enrollmentId: enrollment.id,
        fromBatchId: batch.id,
        toBatchId: picked.id,
      );
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _showEnrollSheet(
    BuildContext context,
    WidgetRef ref,
    List<Student> candidates, {
    required bool waitlist,
  }) async {
    if (candidates.isEmpty) {
      AppSnackbar.info(context, 'All your students are already enrolled.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SheetScaffold(
        title: waitlist ? 'Add to waitlist' : 'Enrol a student',
        subtitle: waitlist
            ? 'This batch is at capacity — picked students join the waitlist.'
            : 'Pick a student to enrol in this batch.',
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: candidates.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = candidates[i];
            return AppListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(s.fullName),
              subtitle: Text(s.parentName),
              trailing: Icon(waitlist ? Icons.queue_outlined : Icons.add),
              onTap: () async {
                await enrollStudent(
                  ref,
                  batchId: batch.id,
                  studentId: s.id,
                  status: waitlist ? 'waitlisted' : 'active',
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            );
          },
        ),
      ),
    );
  }
}

/// Identity + scannable facts header for the batch (§3.2).
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.batch, required this.atCapacity});

  final Batch batch;
  final bool atCapacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cap = batch.capacity;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              AppBadge(
                text: batch.isActive ? 'Active' : 'Archived',
                tone: batch.isActive
                    ? AppBadgeTone.success
                    : AppBadgeTone.neutral,
              ),
              if (cap != null)
                AppBadge(
                  text: atCapacity ? 'At capacity' : 'Spots open',
                  tone: atCapacity
                      ? AppBadgeTone.warning
                      : AppBadgeTone.brand,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _FactRow(
            icon: Icons.schedule_outlined,
            label: 'Schedule',
            value: batch.schedule.summary,
          ),
          Consumer(
            builder: (_, ref, __) {
              final sportLabel = ref.watch(sportDisplayProvider((
                sportId: batch.sportId,
              )));
              if (sportLabel == '—') return const SizedBox.shrink();
              return _FactRow(
                icon: Icons.sports_outlined,
                label: 'Sport',
                value: sportLabel,
              );
            },
          ),
          if (batch.ageGroup != null)
            _FactRow(
              icon: Icons.cake_outlined,
              label: 'Age group',
              value: batch.ageGroup!,
            ),
          if (batch.skillLevel != null)
            _FactRow(
              icon: Icons.bar_chart_outlined,
              label: 'Skill level',
              value: batch.skillLevel!,
            ),
          _FactRow(
            icon: Icons.groups_outlined,
            label: 'Enrolled',
            value: cap != null
                ? '${batch.enrolledCount} of $cap'
                : '${batch.enrolledCount}',
          ),
          if (batch.description != null &&
              batch.description!.trim().isNotEmpty) ...[
            const Divider(height: AppSpacing.xl),
            Text(
              batch.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One labeled icon + value fact line for the header card.
class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The single enrol/waitlist action surfaced in the enrolment section header.
class _EnrollAction extends StatelessWidget {
  const _EnrollAction({required this.atCapacity, required this.onPressed});

  final bool atCapacity;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: Icon(
        atCapacity ? Icons.queue_outlined : Icons.person_add_outlined,
        size: 18,
      ),
      label: Text(atCapacity ? 'Waitlist' : 'Enrol'),
      onPressed: onPressed,
    );
  }
}

/// One reusable enrolment group: a count sub-header + a card of student rows
/// with a status badge and a stable per-row action set. Rendered once per
/// status group (Active / Waitlist / Withdrawn) — never copy-pasted.
class _EnrollmentSection extends StatelessWidget {
  const _EnrollmentSection({
    required this.title,
    required this.tone,
    required this.enrollments,
    required this.byStudent,
    this.onWithdraw,
    this.onPromote,
    this.onTransfer,
  });

  final String title;
  final AppBadgeTone tone;
  final List<Enrollment> enrollments;
  final Map<String, Student> byStudent;
  final Future<void> Function(Enrollment)? onWithdraw;
  final Future<void> Function(Enrollment)? onPromote;
  final Future<void> Function(Enrollment)? onTransfer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: '$title (${enrollments.length})',
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final e in enrollments)
                AppListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    byStudent[e.studentId]?.fullName ?? '(unknown student)',
                  ),
                  subtitle: Align(
                    alignment: Alignment.centerLeft,
                    child: AppBadge(text: title, tone: tone),
                  ),
                  onTap: () {
                    final s = byStudent[e.studentId];
                    if (s == null) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => CoachStudentPage(student: s),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MessageParentButton(studentId: e.studentId),
                      if (onPromote != null)
                        IconButton(
                          tooltip: 'Promote to active',
                          icon: const Icon(Icons.upgrade),
                          onPressed: () => onPromote!(e),
                        ),
                      if (onTransfer != null)
                        IconButton(
                          tooltip: 'Transfer to another batch',
                          icon: const Icon(Icons.swap_horiz),
                          onPressed: () => onTransfer!(e),
                        ),
                      if (onWithdraw != null)
                        IconButton(
                          tooltip: 'Withdraw',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => onWithdraw!(e),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A titled, scrollable bottom-sheet frame (§3.5): drag handle, title row,
/// optional subtitle, and a bounded scrollable body that respects the
/// keyboard inset.
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
