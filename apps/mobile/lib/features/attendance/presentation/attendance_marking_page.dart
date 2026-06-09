import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/attendance/data/attendance.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Per-batch attendance marking screen — v1 "Sports-Light" roster archetype.
///
/// Shows enrolled students for the given batch under an entity-colored hero
/// (present / absent / left summary + human date), lets the coach toggle each
/// student's status with present/absent squares, bulk mark all-present, and add
/// notes in a reserved (non-jittering) area. Saves are upsert-on-(batch,
/// student, date) via [upsertAttendance]; the pinned bottom bar shows the
/// marked count.
class AttendanceMarkingPage extends ConsumerStatefulWidget {
  const AttendanceMarkingPage({
    required this.batch,
    required this.date,
    super.key,
  });

  final Batch batch;
  final DateTime date;

  @override
  ConsumerState<AttendanceMarkingPage> createState() =>
      _AttendanceMarkingPageState();
}

class _AttendanceMarkingPageState extends ConsumerState<AttendanceMarkingPage> {
  /// In-memory edit buffer keyed by studentId. Initialised from the server
  /// snapshot on first frame.
  final Map<String, AttendanceStatus> _statuses = {};
  final Map<String, TextEditingController> _notes = {};
  bool _seeded = false;
  bool _saving = false;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get _humanDate {
    final d = widget.date;
    final weekday = _weekdays[d.weekday - 1];
    final month = _months[d.month - 1];
    return '$weekday, ${d.day} $month ${d.year}';
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(
    List<Student> roster,
    List<AttendanceRecord> existing,
  ) {
    if (_seeded) return;
    final byStudent = {for (final r in existing) r.studentId: r};
    for (final s in roster) {
      final r = byStudent[s.id];
      _statuses[s.id] = r?.status ?? AttendanceStatus.absent;
      _notes[s.id] = TextEditingController(text: r?.notes ?? '');
    }
    _seeded = true;
  }

  void _markAllPresent(List<Student> roster) {
    setState(() {
      for (final s in roster) {
        _statuses[s.id] = AttendanceStatus.present;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final entries = _statuses.entries
          .map((e) => (
                studentId: e.key,
                status: e.value,
                notes: _notes[e.key]?.text.trim().isEmpty ?? true
                    ? null
                    : _notes[e.key]!.text.trim(),
              ))
          .toList();
      await upsertAttendance(
        ref,
        batchId: widget.batch.id,
        date: widget.date,
        entries: entries,
      );
      if (!mounted) return;
      AppSnackbar.success(
        context,
        'Saved attendance for ${entries.length} students.',
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync =
        ref.watch(batchEnrollmentsProvider(widget.batch.id));
    final studentsAsync = ref.watch(studentsProvider);
    final attendanceAsync = ref.watch(attendanceForBatchProvider(
      AttendanceKey(batchId: widget.batch.id, date: widget.date),
    ));

    // Entity-colored hero: a deterministic sport-style pair derived from the
    // batch name, per the v1 entity-detail hero convention.
    final heroColor = colorFromName(widget.batch.name);

    return Scaffold(
      body: enrollmentsAsync.when(
        loading: () => _Shell(
          hero: _hero(present: 0, absent: 0, left: 0, heroColor: heroColor),
          body: const AppSkeletonList(),
        ),
        error: (e, _) => _Shell(
          hero: _hero(present: 0, absent: 0, left: 0, heroColor: heroColor),
          body: AppErrorView(
            message: friendlyError(e),
            onRetry: () =>
                ref.invalidate(batchEnrollmentsProvider(widget.batch.id)),
          ),
        ),
        data: (enrollments) {
          final allStudents = studentsAsync.valueOrNull ?? const <Student>[];
          final roster = _rosterFromState(enrollments, allStudents);
          if (roster.isEmpty) {
            return _Shell(
              hero: _hero(present: 0, absent: 0, left: 0, heroColor: heroColor),
              body: const AppEmptyState(
                icon: Icons.group_off_outlined,
                title: 'No students enrolled',
                subtitle:
                    'There are no active students in this batch yet. Enrol '
                    'students before marking attendance.',
              ),
            );
          }
          final attendance = attendanceAsync.valueOrNull;
          if (attendance == null) {
            return _Shell(
              hero: _hero(present: 0, absent: 0, left: 0, heroColor: heroColor),
              body: const AppSkeletonList(),
            );
          }
          _seed(roster, attendance);

          final present = roster
              .where((s) => _statuses[s.id] == AttendanceStatus.present)
              .length;
          final absent = roster
              .where((s) => _statuses[s.id] == AttendanceStatus.absent)
              .length;
          // "Left" = neither plainly present nor plainly absent (late/excused).
          final left = roster.length - present - absent;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _hero(
                      present: present,
                      absent: absent,
                      left: left,
                      heroColor: heroColor,
                    ),
                    // Roster header sits just under the hero band.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppSectionHeader(
                              title: 'Roster · ${roster.length}',
                              icon: Icons.groups_outlined,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _markAllPresent(roster),
                            icon: const Icon(Icons.done_all_rounded, size: 18),
                            label: const Text('All present'),
                          ),
                        ],
                      ),
                    ),
                    ...List.generate(roster.length, (i) {
                      final s = roster[i];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        child: _RosterRow(
                          student: s,
                          status: _statuses[s.id]!,
                          notesCtrl: _notes[s.id]!,
                          onStatus: (v) =>
                              setState(() => _statuses[s.id] = v),
                        ),
                      );
                    }),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
              _SaveFooter(
                present: present,
                total: roster.length,
                saving: _saving,
                onSave: _save,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Entity-colored hero band: back button, batch name + schedule chip, and a
  /// translucent present / absent / left summary strip.
  Widget _hero({
    required int present,
    required int absent,
    required int left,
    required Color heroColor,
  }) {
    final theme = Theme.of(context);
    final schedule = widget.batch.schedule.summary;
    return AppGradientHeader(
      colors: [heroColor.withValues(alpha: 0.92), heroColor],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.batch.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: AppType.heavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _humanDate,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (schedule != 'No schedule') ...[
            const SizedBox(height: AppSpacing.md),
            AppGlassChip(schedule, icon: Icons.schedule_rounded),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppHeroStatRow(
            stats: [
              ('$present', 'Present'),
              ('$absent', 'Absent'),
              ('$left', 'Left'),
            ],
          ),
        ],
      ),
    );
  }

  List<Student> _rosterFromState(
    List<Enrollment> enrollments,
    List<Student> allStudents,
  ) {
    final byId = {for (final s in allStudents) s.id: s};
    final activeIds = enrollments
        .where((e) => e.status == 'active')
        .map((e) => e.studentId)
        .toList();
    return activeIds
        .map((id) => byId[id])
        .whereType<Student>()
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }
}

/// Hero band + a body region below it (used for loading / error / empty so the
/// hero always renders and the back button stays reachable).
class _Shell extends StatelessWidget {
  const _Shell({required this.hero, required this.body});

  final Widget hero;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        hero,
        Expanded(child: body),
      ],
    );
  }
}

/// One student's roster row: gradient avatar, name + a one-line meta, an
/// absent/present toggle pair, and a reserved (always-present, non-jittering)
/// note field that expands for the nuanced late/excused states.
class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.student,
    required this.status,
    required this.notesCtrl,
    required this.onStatus,
  });

  final Student student;
  final AttendanceStatus status;
  final TextEditingController notesCtrl;
  final ValueChanged<AttendanceStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sem = AppSemanticColors.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(student.fullName, size: 42),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: AppType.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _MetaLine(student: student),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _Toggle(
                icon: Icons.close_rounded,
                active: status == AttendanceStatus.absent,
                color: sem.danger,
                tooltip: 'Absent',
                onTap: () => onStatus(AttendanceStatus.absent),
              ),
              const SizedBox(width: AppSpacing.sm),
              _Toggle(
                icon: Icons.check_rounded,
                active: status == AttendanceStatus.present,
                color: sem.success,
                tooltip: 'Present',
                onTap: () => onStatus(AttendanceStatus.present),
              ),
            ],
          ),
          // Nuanced states (late / excused) for the cases the two squares can't
          // express — kept compact so the common present/absent flow stays fast.
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatusChip(
                    label: 'Late',
                    icon: Icons.access_time_rounded,
                    tone: AppBadgeTone.warning,
                    selected: status == AttendanceStatus.late,
                    onTap: () => onStatus(AttendanceStatus.late),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusChip(
                    label: 'Excused',
                    icon: Icons.event_busy_rounded,
                    tone: AppBadgeTone.info,
                    selected: status == AttendanceStatus.excused,
                    onTap: () => onStatus(AttendanceStatus.excused),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Reserved note area — always rendered so the card height never
          // jitters as the status changes.
          TextField(
            controller: notesCtrl,
            style: theme.textTheme.bodyMedium,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// One-line muted meta under a roster name: an "Unpaid" flag takes precedence,
/// else the skill level if present.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    if (student.feeOverdue) {
      return const AppBadge(
        text: 'Unpaid',
        tone: AppBadgeTone.danger,
        icon: Icons.error_outline_rounded,
      );
    }
    final theme = Theme.of(context);
    final meta = student.skillLevel ?? 'Active';
    return Text(
      meta,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A square present/absent toggle: filled in its color when active, a soft tint
/// otherwise. Animates the fill so taps feel responsive.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.active,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? color : color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              icon,
              color: active ? Colors.white : color,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact selectable status chip for the nuanced late / excused states.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final AppBadgeTone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sem = AppSemanticColors.of(context);
    final color = switch (tone) {
      AppBadgeTone.warning => sem.warning,
      AppBadgeTone.info => sem.info,
      AppBadgeTone.success => sem.success,
      AppBadgeTone.danger => sem.danger,
      _ => theme.colorScheme.primary,
    };
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.14)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? color : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? color : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      selected ? color : theme.colorScheme.onSurfaceVariant,
                  fontWeight: AppType.semibold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned bottom save bar with a floating-shadow lift and a present count.
class _SaveFooter extends StatelessWidget {
  const _SaveFooter({
    required this.present,
    required this.total,
    required this.saving,
    required this.onSave,
  });

  final int present;
  final int total;
  final bool saving;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: AppShadows.floating,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                saving ? 'Saving…' : 'Save · $present/$total present',
              ),
              onPressed: saving ? null : onSave,
            ),
          ),
        ),
      ),
    );
  }
}
