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
import 'package:playhub/features/coach/data/coach_home_providers.dart';
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
    // center_admin may manage MULTIPLE centers (user_centers) — check the batch
    // against the full grant set, not just the primary center.
    final myCenters =
        ref.watch(myCenterIdsProvider).valueOrNull ?? const <String>{};
    final inMyCenter =
        batch.centerId == null || myCenters.contains(batch.centerId);
    final scopeOk = !isCenterScoped || inMyCenter;
    final canManageEnroll = caps.manageBatches && scopeOk;
    final canMarkAttendance = caps.markAttendance && scopeOk;
    // Fees/discounts are finance: admin-only write, center_admin view-only.
    final canManageFinance = caps.manageFinance;
    final canViewFinance = caps.viewRevenue;

    final atCapacity = _atCapacity();
    final sportLabel = ref.watch(sportDisplayProvider((sportId: batch.sportId)));
    final hasSport = sportLabel != '—';
    // Entity-colored hero: tie the band to the batch's sport (falling back to
    // the brand orange when the batch has no sport).
    final accent = hasSport ? colorFromName(sportLabel) : AppPalette.brandPrimary;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Sport-colored detail hero: back/chat/edit/more circle buttons, a big
          // gradient avatar, the batch name + sport sub-line, and status chips.
          AppGradientHeader(
            colors: [accent.withValues(alpha: 0.92), accent],
            child: Column(
              children: [
                Row(
                  children: [
                    AppCircleIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    _HeroChatButton(batchId: batch.id),
                    if (canMarkAttendance) ...[
                      const SizedBox(width: AppSpacing.sm),
                      AppCircleIconButton(
                        icon: Icons.fact_check_outlined,
                        tooltip: 'Mark attendance',
                        onTap: () {
                          final today = DateTime.now();
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => AttendanceMarkingPage(
                                batch: batch,
                                date: DateTime(
                                  today.year,
                                  today.month,
                                  today.day,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    if (canManageEnroll) ...[
                      const SizedBox(width: AppSpacing.sm),
                      AppCircleIconButton(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit batch',
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => BatchFormPage(existing: batch),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _HeroMoreButton(
                        onSelected: (v) => _confirmSetActive(
                          context,
                          ref,
                          makeActive: v == 'restore',
                        ),
                        isActive: batch.isActive,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppAvatar(batch.name, size: 78, color: Colors.white),
                const SizedBox(height: AppSpacing.md),
                Text(
                  batch.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Colors.white),
                ),
                if (hasSport) ...[
                  const SizedBox(height: 4),
                  Text(
                    sportLabel,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  alignment: WrapAlignment.center,
                  children: [
                    AppGlassChip(
                      batch.isActive ? 'Active' : 'Archived',
                      icon: batch.isActive
                          ? Icons.verified_rounded
                          : Icons.archive_outlined,
                    ),
                    if (batch.capacity != null)
                      AppGlassChip(
                        atCapacity ? 'At capacity' : 'Spots open',
                        icon: atCapacity
                            ? Icons.event_busy_outlined
                            : Icons.event_available_outlined,
                      ),
                    if (batch.skillLevel != null)
                      AppGlassChip(
                        batch.skillLevel!,
                        icon: Icons.bar_chart_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Body overlaps the hero band upward, v1-style.
          Transform.translate(
            offset: const Offset(0, -AppSpacing.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Floating 3-up mini-stat row overlapping the band.
                  _MiniStatRow(batch: batch, accent: accent),
                  const SizedBox(height: AppSpacing.xl),

                  // Capacity meter + scannable batch facts.
                  const AppSectionHeader(
                    title: 'Overview',
                    icon: Icons.info_outline,
                  ),
                  _OverviewCard(
                    batch: batch,
                    atCapacity: atCapacity,
                    accent: accent,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Finance: view for any revenue-capable role; write only when
                  // canManageFinance (admin) — center_admin is view-only.
                  if (canViewFinance) ...[
                    BatchFeesSection(
                      batchId: batch.id,
                      canManage: canManageFinance,
                      daysPerWeek: batch.schedule.days.isEmpty
                          ? null
                          : batch.schedule.days.length,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    BatchDiscountsSection(
                      batchId: batch.id,
                      canManage: canManageFinance,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // Enrolment, grouped by status (one reusable section per
                  // group, each with a count sub-header).
                  AppSectionHeader(
                    title: 'Enrolment',
                    icon: Icons.groups_outlined,
                    trailing: canManageEnroll
                        ? _EnrollAction(
                            atCapacity: atCapacity,
                            onPressed: () async {
                              final students =
                                  studentsAsync.valueOrNull ?? const [];
                              final enrolled =
                                  enrollmentsAsync.valueOrNull ?? const [];
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
                                waitlist: atCapacity,
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
                              ? 'Use Enrol to add the first student to this '
                                  'batch.'
                              : 'Students enrolled in this batch will appear '
                                  'here.',
                        );
                      }
                      final byId = {
                        for (final s
                            in (studentsAsync.valueOrNull ?? const <Student>[]))
                          s.id: s,
                      };
                      final active = enrollments
                          .where((e) => e.status == 'active')
                          .toList();
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
                              onPromote: (!canManageEnroll || atCapacity)
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
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Archive (soft-delete) or restore the batch. Archiving keeps enrollment +
  /// attendance history (a hard delete would cascade and wipe it) and is
  /// reversible. Both list providers are invalidated so the admin Batches tab
  /// and the head-coach "My batches" tab refresh, then we pop back to the list.
  Future<void> _confirmSetActive(
    BuildContext context,
    WidgetRef ref, {
    required bool makeActive,
  }) async {
    if (!makeActive) {
      final ok = await confirmAction(
        context,
        title: 'Archive this batch?',
        message:
            "It will be hidden from active lists and today's sessions. "
            'Enrollments and attendance history are kept, and you can restore '
            'it later.',
        confirmLabel: 'Archive',
        destructive: true,
      );
      if (!ok) return;
    }
    try {
      await setBatchActive(ref, batch.id, isActive: makeActive);
      ref
        ..invalidate(batchesProvider)
        ..invalidate(myBatchesProvider);
      if (!context.mounted) return;
      AppSnackbar.success(
        context,
        makeActive ? 'Batch restored.' : 'Batch archived.',
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
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
              leading: AppAvatar(b.name, size: 40),
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
              leading: AppAvatar(s.fullName, size: 40),
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

/// Batch chat opened from the hero — wraps [BatchChatButton] (which is a plain
/// IconButton in compact mode) in a frosted circle so it reads as a hero action.
class _HeroChatButton extends StatelessWidget {
  const _HeroChatButton({required this.batchId});

  final String batchId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: IconTheme(
        data: const IconThemeData(color: Colors.white, size: 22),
        child: BatchChatButton(batchId: batchId, compact: true),
      ),
    );
  }
}

/// The hero "more" (archive/restore) action — a frosted circle wrapping the
/// archive popup so it matches the other hero circle buttons.
class _HeroMoreButton extends StatelessWidget {
  const _HeroMoreButton({
    required this.onSelected,
    required this.isActive,
  });

  final ValueChanged<String> onSelected;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
        onSelected: onSelected,
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: isActive ? 'archive' : 'restore',
            child: Text(isActive ? 'Archive batch' : 'Restore batch'),
          ),
        ],
      ),
    );
  }
}

/// Floating 3-up mini-stat row that overlaps the hero band — enrolled count,
/// capacity (or "Open" when uncapped), and sessions per week from the schedule.
class _MiniStatRow extends StatelessWidget {
  const _MiniStatRow({required this.batch, required this.accent});

  final Batch batch;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cap = batch.capacity;
    final perWeek = batch.schedule.days.length;
    final semantics = AppSemanticColors.of(context);
    final atCapacity = cap != null && batch.enrolledCount >= cap;
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            value: '${batch.enrolledCount}',
            label: 'Enrolled',
            icon: Icons.groups_rounded,
            tint: accent,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MiniStat(
            value: cap != null ? '$cap' : '∞',
            label: 'Capacity',
            icon: Icons.event_seat_rounded,
            tint: atCapacity ? semantics.warning : AppPalette.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MiniStat(
            value: '$perWeek',
            label: perWeek == 1 ? 'Day / wk' : 'Days / wk',
            icon: Icons.calendar_today_rounded,
            tint: AppPalette.brandPrimary,
          ),
        ),
      ],
    );
  }
}

/// A single floating mini-stat tile — a tinted icon, a heavy value, and a muted
/// label, on a soft-shadowed card so it lifts over the hero band.
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.tint,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Column(
        children: [
          Icon(icon, color: tint, size: 22),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: tint,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Overview card: a capacity meter (when capped) plus scannable batch facts
/// (schedule, sport, age group, skill level) and an optional description.
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.batch,
    required this.atCapacity,
    required this.accent,
  });

  final Batch batch;
  final bool atCapacity;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    final cap = batch.capacity;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cap != null) ...[
            AppLabeledProgress(
              label: 'Capacity',
              value: cap == 0 ? 0 : batch.enrolledCount / cap,
              trailing: '${batch.enrolledCount} / $cap',
              color: atCapacity ? semantics.warning : accent,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          _FactRow(
            icon: Icons.schedule_outlined,
            label: 'Schedule',
            value: batch.schedule.summary,
          ),
          Consumer(
            builder: (_, ref, __) {
              final sportLabel = ref.watch(
                sportDisplayProvider((sportId: batch.sportId)),
              );
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

/// One labeled icon + value fact line for the overview card.
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
                  wrapLeading: false,
                  leading: AppAvatar(
                    byStudent[e.studentId]?.fullName ?? '?',
                    size: 40,
                  ),
                  title: Text(
                    byStudent[e.studentId]?.fullName ?? '(unknown student)',
                  ),
                  subtitle: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        AppBadge(text: title, tone: tone),
                        if (byStudent[e.studentId]?.feeOverdue ?? false)
                          const AppBadge(
                            text: 'Unpaid',
                            tone: AppBadgeTone.danger,
                          ),
                      ],
                    ),
                  ),
                  onTap: () {
                    final s = byStudent[e.studentId];
                    if (s == null) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) =>
                            CoachStudentPage(student: s, batchId: e.batchId),
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
