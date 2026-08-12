import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/payment_checkout.dart';
import 'package:playhub/features/billing/data/razorpay_checkout.dart';
import 'package:playhub/features/billing/presentation/payment_offline_dialog.dart';
import 'package:playhub/features/events/presentation/events_page.dart';
import 'package:playhub/features/insights/presentation/student_insights_page.dart';
import 'package:playhub/features/parent/data/parent_providers.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Parent / student dashboard. Shows a persistent linked-student switcher,
/// the priority "this week" sections (next session + outstanding dues), then
/// the heavier visualisations (attendance heatmap + weekly bars, performance
/// line, media gallery) grouped under section headers, and an events link.
///
/// The wordmark + account entry point live in the parent home shell's AppBar;
/// this tab renders only the scrollable body. Razorpay checkout for an
/// outstanding invoice runs from here, behind a confirmation step.
class ParentDashboardTab extends ConsumerStatefulWidget {
  const ParentDashboardTab({super.key});

  @override
  ConsumerState<ParentDashboardTab> createState() => _ParentDashboardTabState();
}

class _ParentDashboardTabState extends ConsumerState<ParentDashboardTab> {
  String? _selectedStudentId;

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(myLinkedStudentsProvider);
    return Scaffold(
      body: studentsAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(myLinkedStudentsProvider),
        ),
        data: (students) {
          if (students.isEmpty) {
            return const AppEmptyState(
              icon: Icons.group_outlined,
              title: 'No students linked yet',
              subtitle:
                  'Ask your academy admin to link a student to your account '
                  'so their schedule, attendance, and dues show up here.',
            );
          }
          _selectedStudentId ??= students.first.id;
          final selected = students.firstWhere(
            (s) => s.id == _selectedStudentId,
            orElse: () => students.first,
          );
          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(myLinkedStudentIdsProvider)
                ..invalidate(myLinkedStudentsProvider)
                ..invalidate(studentAttendanceProvider(selected.id))
                ..invalidate(studentAttendanceWeeklyProvider(selected.id))
                ..invalidate(studentPerformanceProvider(selected.id))
                ..invalidate(mediaForStudentProvider(selected.id))
                ..invalidate(studentOutstandingDuesProvider(selected.id))
                ..invalidate(studentUpcomingSessionsProvider(selected.id))
                ..invalidate(myLinkedStudentBatchesProvider(selected.id));
            },
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // v1 identity hero: avatar + name + sport, the multi-child
                // switcher, and a headline stat strip derived from the dues +
                // attendance the body cards already load (no new queries).
                _StudentHero(
                  students: students,
                  selected: selected,
                  onSelect: (id) => setState(() => _selectedStudentId = id),
                ),
                // Body overlaps the hero band upward, v1-style.
                Transform.translate(
                  offset: const Offset(0, -AppSpacing.lg),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Priority: what matters right now sits at the top.
                        const AppSectionHeader(
                          title: 'This week',
                          icon: Icons.event_available_outlined,
                        ),
                        _UpcomingSessionsCard(studentId: selected.id),
                        const SizedBox(height: AppSpacing.md),
                        _OutstandingCard(studentId: selected.id),
                        const SizedBox(height: AppSpacing.xl),

                        const AppSectionHeader(
                          title: 'Batches',
                          icon: Icons.groups_2_outlined,
                        ),
                        _BatchesCard(studentId: selected.id),
                        const SizedBox(height: AppSpacing.xl),

                        const AppSectionHeader(
                          title: 'Attendance',
                          icon: Icons.fact_check_outlined,
                        ),
                        _AttendanceCard(studentId: selected.id),
                        const SizedBox(height: AppSpacing.xl),

                        const AppSectionHeader(
                          title: 'Performance',
                          icon: Icons.show_chart_rounded,
                        ),
                        _PerformanceCard(studentId: selected.id),
                        const SizedBox(height: AppSpacing.xl),

                        const AppSectionHeader(
                          title: 'AI insights',
                          icon: Icons.auto_awesome_outlined,
                        ),
                        AppCard(
                          padding: EdgeInsets.zero,
                          child: AppListTile(
                            leading: const Icon(Icons.auto_awesome_outlined),
                            title: const Text('AI insights'),
                            subtitle:
                                const Text('Progress summary, generated by AI'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => StudentInsightsPage(
                                  studentId: selected.id,
                                  studentName: selected.fullName,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        const AppSectionHeader(
                          title: 'Photos & videos',
                          icon: Icons.photo_library_outlined,
                        ),
                        _MediaGalleryCard(studentId: selected.id),
                        const SizedBox(height: AppSpacing.xl),

                        const AppSectionHeader(
                          title: 'More',
                          icon: Icons.apps_rounded,
                        ),
                        AppCard(
                          padding: EdgeInsets.zero,
                          child: AppListTile(
                            leading:
                                const Icon(Icons.emoji_events_outlined),
                            title: const Text('Events'),
                            subtitle: const Text(
                              'Browse + register for tournaments',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => const EventsPage(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The v1 identity hero: the selected student's avatar + name + sport on a
/// brand-gradient band, a glass-chip switcher when more than one child is
/// linked, and a headline stat strip (attendance % + dues) derived from data
/// the body cards already load — no extra queries. Rendered for a single
/// student too, so the layout never appears/disappears by count.
/// The address to show for a student: their own login email when they have one,
/// otherwise the parent's. Null when neither is on file (nothing is rendered).
String? _contactEmail(Student s) {
  final own = s.email?.trim();
  if (own != null && own.isNotEmpty) return own;
  final parent = s.parentEmail?.trim();
  if (parent != null && parent.isNotEmpty) return parent;
  return null;
}

class _StudentHero extends ConsumerWidget {
  const _StudentHero({
    required this.students,
    required this.selected,
    required this.onSelect,
  });

  final List<Student> students;
  final Student selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: selected.sportId)),
    );
    final photoUrl =
        ref.watch(storageServiceProvider).publicAvatarUrl(selected.photo);

    // Both providers are already watched by the body cards below for this
    // student, so deriving the hero stats here adds no new network calls.
    final attendance =
        ref.watch(studentAttendanceProvider(selected.id)).valueOrNull;
    final dues =
        ref.watch(studentOutstandingDuesProvider(selected.id)).valueOrNull;

    final stats = <(String, String)>[];
    if (attendance != null && attendance.isNotEmpty) {
      final present = attendance.where((d) => d.status == 'present').length;
      final pct = (present * 100 / attendance.length).round();
      stats.add(('$pct%', 'Attendance'));
    }
    if (dues != null) {
      final balance = dues.fold<double>(0, (sum, r) => sum + r.balance);
      stats.add(('₹${balance.toStringAsFixed(0)}', 'Dues'));
    }

    return AppGradientHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AvatarCircle(
                size: 56,
                url: photoUrl,
                fallback:
                    selected.firstName.isEmpty ? '?' : selected.firstName[0],
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selected.firstName} ${selected.lastName}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: AppType.heavy,
                      ),
                    ),
                    if (sportLabel != '—') ...[
                      const SizedBox(height: 2),
                      Text(
                        sportLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                    // Contact line: the student's own address when they have a
                    // login, else the parent's. It was shown nowhere on this
                    // dashboard, which read as "the app lost my email".
                    if (_contactEmail(selected) case final email?) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.mail_outline_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (students.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final s in students)
                  _SwitcherChip(
                    label: s.firstName,
                    selected: s.id == selected.id,
                    onTap: () => onSelect(s.id),
                  ),
              ],
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AppHeroStatRow(stats: stats),
          ],
        ],
      ),
    );
  }
}

/// A child-switcher chip on the hero: a frosted [AppGlassChip] when unselected,
/// a solid white pill (brand-ink text) when selected. Tap drives the selection;
/// wrapped in [InkWell]/[Semantics] so it stays tap + screen-reader accessible.
class _SwitcherChip extends StatelessWidget {
  const _SwitcherChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget chip;
    if (selected) {
      chip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppPalette.brandPrimaryDark,
                fontWeight: AppType.bold,
              ),
        ),
      );
    } else {
      chip = AppGlassChip(label);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: chip),
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.size,
    required this.url,
    required this.fallback,
  });
  final double size;
  final String? url;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return CircleAvatar(
        radius: size / 2,
        child: Text(fallback, style: Theme.of(context).textTheme.titleLarge),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => CircleAvatar(
          radius: size / 2,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: size / 2,
          child: Text(fallback, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
    );
  }
}

class _UpcomingSessionsCard extends ConsumerStatefulWidget {
  const _UpcomingSessionsCard({required this.studentId});
  final String studentId;

  @override
  ConsumerState<_UpcomingSessionsCard> createState() =>
      _UpcomingSessionsCardState();
}

class _UpcomingSessionsCardState extends ConsumerState<_UpcomingSessionsCard> {
  /// Sessions are sorted soonest-first by the provider, so showing the first
  /// few = the most relevant (nearest in time). The rest of the week is one
  /// "Read more" tap away — keeps the dashboard glanceable without hiding data.
  static const _collapsedCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(studentUpcomingSessionsProvider(widget.studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upcoming sessions',
            style: theme.textTheme.titleMedium,
          ),
          Text(
            'Next 7 days',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(friendlyError(e)),
            data: (sessions) {
              if (sessions.isEmpty) {
                return Text(
                  'No sessions scheduled this week',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              final hasMore = sessions.length > _collapsedCount;
              final visible = (_expanded || !hasMore)
                  ? sessions
                  : sessions.take(_collapsedCount).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in visible)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(s.batchName),
                      subtitle: Text(
                        s.coachDisplayName == null
                            ? s.whenLabel
                            : '${s.whenLabel}  •  Coach ${s.coachDisplayName}',
                      ),
                    ),
                  if (hasMore)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                        ),
                        label: Text(
                          _expanded
                              ? 'Show less'
                              : 'Read more (${sessions.length - _collapsedCount} more)',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BatchesCard extends ConsumerWidget {
  const _BatchesCard({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(myLinkedStudentBatchesProvider(studentId));
    return AppCard(
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => Text(friendlyError(e)),
        data: (rows) {
          if (rows.isEmpty) {
            return Text(
              'No active batches',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: AppSpacing.xl),
                _BatchRow(row: rows[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BatchRow extends ConsumerWidget {
  const _BatchRow({required this.row});
  final StudentBatchRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sportLabel = ref.watch(sportDisplayProvider((sportId: row.sportId)));
    final coachPhotoUrl = ref
        .watch(storageServiceProvider)
        .publicAvatarUrl(row.coachPhoto);
    final coachName = row.coachDisplayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.batchName + (sportLabel != '—' ? '  •  $sportLabel' : ''),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Icon(
              Icons.schedule,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                row.scheduleSummary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (coachName.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarCircle(
                size: 36,
                url: coachPhotoUrl,
                fallback: coachName.isEmpty ? '?' : coachName[0],
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Coach $coachName',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (row.coachQualifications.isNotEmpty)
                      Text(
                        row.coachQualifications.join(', '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AttendanceCard extends ConsumerWidget {
  const _AttendanceCard({required this.studentId});
  final String studentId;

  Color _color(BuildContext c, String status) {
    final semantics = AppSemanticColors.of(c);
    switch (status) {
      case 'present':
        return semantics.success;
      case 'absent':
        return semantics.danger;
      case 'late':
        return semantics.warning;
      case 'excused':
        return semantics.info;
    }
    return Theme.of(c).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(studentAttendanceProvider(studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 60 days',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(friendlyError(e)),
            data: (days) {
              if (days.isEmpty) {
                return Text(
                  'No records yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              final total = days.length;
              final present = days.where((d) => d.status == 'present').length;
              final pct = (present * 100 / total).toStringAsFixed(0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final d in days)
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: _color(context, d.status),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final entry in const [
                        ('present', 'Present'),
                        ('late', 'Late'),
                        ('absent', 'Absent'),
                        ('excused', 'Excused'),
                      ])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _color(context, entry.$1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              entry.$2,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '$present / $total present ($pct%)',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Weekly % · last 4 weeks',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _WeeklyAttendanceChart(studentId: studentId),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WeeklyAttendanceChart extends ConsumerWidget {
  const _WeeklyAttendanceChart({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(studentAttendanceWeeklyProvider(studentId));
    return async.when(
      loading: () => const SizedBox(
        height: 40,
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text(friendlyError(e)),
      data: (weeks) {
        if (weeks.every((w) => w.total == 0)) {
          return Text(
            'Not enough data',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        final primary = theme.colorScheme.primary;
        return SizedBox(
          height: 120,
          child: BarChart(
            BarChartData(
              maxY: 100,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              barGroups: [
                for (var i = 0; i < weeks.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: weeks[i].pct,
                        color: primary,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadius.sm),
                        ),
                      ),
                    ],
                  ),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: theme.colorScheme.outlineVariant,
                  strokeWidth: 0.5,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 25,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 18,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= weeks.length) {
                        return const SizedBox.shrink();
                      }
                      final ws = weeks[i].weekStart;
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          '${ws.day}/${ws.month}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, __, ___) {
                    final w = weeks[group.x];
                    return BarTooltipItem(
                      'Week of ${w.weekStart.day}/${w.weekStart.month}\n'
                      '${w.present}/${w.total}'
                      ' (${w.pct.toStringAsFixed(0)}%)',
                      theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onInverseSurface,
                          ) ??
                          TextStyle(
                            color: theme.colorScheme.onInverseSurface,
                          ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PerformanceCard extends ConsumerWidget {
  const _PerformanceCard({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(studentPerformanceProvider(studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assessment trend',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(friendlyError(e)),
            data: (pts) {
              if (pts.isEmpty) {
                return Text(
                  'No assessments yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              final primary = theme.colorScheme.primary;
              return SizedBox(
                height: 160,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 10,
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < pts.length; i++)
                            FlSpot(i.toDouble(), pts[i].score),
                        ],
                        isCurved: true,
                        color: primary,
                        barWidth: 3,
                        belowBarData: BarAreaData(
                          show: true,
                          color: primary.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 2.5,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: theme.colorScheme.outlineVariant,
                        strokeWidth: 0.5,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      bottomTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: 2.5,
                          getTitlesWidget: (v, _) => Text(
                            v.toStringAsFixed(0),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          final p = pts[s.x.toInt()];
                          final d = p.date;
                          final dStr =
                              '${d.year}-${d.month.toString().padLeft(2, '0')}'
                              '-${d.day.toString().padLeft(2, '0')}';
                          return LineTooltipItem(
                            '$dStr\n${p.score.toStringAsFixed(1)}/10',
                            theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onInverseSurface,
                                ) ??
                                TextStyle(
                                  color: theme.colorScheme.onInverseSurface,
                                ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MediaGalleryCard extends ConsumerWidget {
  const _MediaGalleryCard({required this.studentId});
  final String studentId;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    PerformanceMedia m,
  ) async {
    final storage = ref.read(storageServiceProvider);
    try {
      final url = await storage.signedPerformanceMediaUrl(m.filePath);
      final ok = await launcher.launchUrl(
        Uri.parse(url),
        mode: launcher.LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        AppSnackbar.error(context, 'Could not open file.');
      }
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(mediaForStudentProvider(studentId));
    return AppCard(
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => Text(friendlyError(e)),
        data: (media) {
          if (media.isEmpty) {
            return Text(
              'No photos or videos shared yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }
          return SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: media.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, i) => _MediaThumb(
                media: media[i],
                onTap: () => _open(context, ref, media[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MediaThumb extends ConsumerWidget {
  const _MediaThumb({required this.media, required this.onTap});
  final PerformanceMedia media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    final isVideo = media.mediaType == 'video';
    final Widget inner;
    if (isVideo) {
      inner = Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: fill),
          const Center(child: Icon(Icons.play_circle_outline, size: 30)),
        ],
      );
    } else {
      final urlAsync = ref.watch(performanceMediaUrlProvider(media.filePath));
      inner = urlAsync.when(
        loading: () => ColoredBox(color: fill),
        error: (_, __) => ColoredBox(
          color: fill,
          child: const Icon(Icons.broken_image_outlined),
        ),
        data: (url) => CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => ColoredBox(color: fill),
          errorWidget: (_, __, ___) => ColoredBox(
            color: fill,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(width: 96, height: 96, child: inner),
      ),
    );
  }
}

class _OutstandingCard extends ConsumerStatefulWidget {
  const _OutstandingCard({required this.studentId});
  final String studentId;

  @override
  ConsumerState<_OutstandingCard> createState() => _OutstandingCardState();
}

class _OutstandingCardState extends ConsumerState<_OutstandingCard> {
  // Invoice ID currently being paid / downloaded — shows a spinner on that row
  // and disables all other buttons to prevent concurrent in-flight payments.
  String? _payingId;
  String? _downloadingId;

  Future<bool> _confirmPay(BuildContext context, OutstandingDues r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay invoice'),
        content: Text(
          'Pay ₹${r.balance.toStringAsFixed(0)} towards invoice '
          "${r.invoiceNumber}? You will be taken to the academy's "
          'secure payment gateway to complete your payment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Pay ₹${r.balance.toStringAsFixed(0)}'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Render the invoice as a PDF (generate-invoice-pdf runs under the parent's
  /// JWT + RLS — they can read their own student's invoice) and open it.
  Future<void> _downloadInvoice(BuildContext context, String invoiceId) async {
    setState(() => _downloadingId = invoiceId);
    try {
      final url = await generateInvoiceReceipt(ref, invoiceId);
      if (!context.mounted) return;
      final ok = await launcher.launchUrl(
        Uri.parse(url),
        mode: launcher.LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        AppSnackbar.error(context, 'Could not open the invoice.');
      }
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _payInvoice(BuildContext context, OutstandingDues r) async {
    final confirmed = await _confirmPay(context, r);
    if (!confirmed || !context.mounted) return;

    setState(() => _payingId = r.invoiceId);
    final client = ref.read(supabaseClientProvider);
    final profile = ref.read(currentProfileProvider).valueOrNull;
    final academy = ref.read(myAcademyProvider).valueOrNull;
    final checkout = PaymentCheckout(client);
    try {
      Future<CheckoutResult> start() => checkout.payInvoice(
            context: context,
            invoiceId: r.invoiceId,
            academyName: academy?.name ?? 'PlayHub',
            prefillEmail: profile?.email,
            prefillContact: profile?.phone,
          );
      var result = await start();
      // Offline before the charge could start → retry dialog, not a snackbar
      // the parent can't act on. Nothing was charged, so retrying is safe.
      while (result is CheckoutFailure && result.isNetwork) {
        if (!context.mounted) return;
        final retry = await showPaymentOfflineDialog(
          context,
          message: result.message,
        );
        if (!retry) break;
        result = await start();
      }
      if (!context.mounted) return;
      switch (result) {
        case CheckoutSuccess():
          AppSnackbar.success(context, 'Payment received');
          // Webhook will update the invoice; refresh the dues list so the
          // row drops out without waiting for the user to pull-to-refresh.
          ref.invalidate(studentOutstandingDuesProvider(widget.studentId));
        case CheckoutExternalWallet(:final walletName):
          AppSnackbar.info(context, 'Continuing in $walletName…');
        case CheckoutFailure(:final message):
          AppSnackbar.error(context, 'Payment failed: $message');
      }
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _payingId = null);
    }
  }

  AppBadgeTone _toneFor(String status) {
    switch (status) {
      case 'overdue':
        return AppBadgeTone.danger;
      case 'partial':
        return AppBadgeTone.warning;
    }
    return AppBadgeTone.info;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(studentOutstandingDuesProvider(widget.studentId));
    final busy = _payingId != null || _downloadingId != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Outstanding dues',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(friendlyError(e)),
            data: (rows) {
              if (rows.isEmpty) {
                return Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: AppSemanticColors.of(context).success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Nothing due right now',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: AppSpacing.lg),
                    _DuesRow(
                      row: rows[i],
                      tone: _toneFor(rows[i].status),
                      isPaying: _payingId == rows[i].invoiceId,
                      isDownloading: _downloadingId == rows[i].invoiceId,
                      disabled: busy,
                      onPay: () => _payInvoice(context, rows[i]),
                      onDownload: () =>
                          _downloadInvoice(context, rows[i].invoiceId),
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
}

class _DuesRow extends StatelessWidget {
  const _DuesRow({
    required this.row,
    required this.tone,
    required this.onPay,
    required this.onDownload,
    this.isPaying = false,
    this.isDownloading = false,
    this.disabled = false,
  });

  final OutstandingDues row;
  final AppBadgeTone tone;
  final VoidCallback onPay;
  final VoidCallback onDownload;
  final bool isPaying;
  final bool isDownloading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueStr = '${row.dueDate.year}-'
        '${row.dueDate.month.toString().padLeft(2, '0')}-'
        '${row.dueDate.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.invoiceNumber,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Due $dueStr',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${row.balance.toStringAsFixed(0)}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                AppBadge(text: row.status, tone: tone),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: disabled ? null : onDownload,
              icon: isDownloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Invoice'),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.tonal(
                onPressed: disabled ? null : onPay,
                child: isPaying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pay'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
