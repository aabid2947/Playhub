import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/profile_page.dart';
import 'package:playhub/features/billing/data/razorpay_checkout.dart';
import 'package:playhub/features/events/presentation/events_page.dart';
import 'package:playhub/features/parent/data/parent_providers.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Parent / student dashboard. Shows linked-students switcher, attendance
/// calendar (last 60 days), performance line, and outstanding dues.
/// Razorpay checkout for outstanding invoices is triggered from this view.
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
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
      body: studentsAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(message: friendlyError(e)),
        data: (students) {
          if (students.isEmpty) {
            return const AppEmptyState(
              icon: Icons.group_outlined,
              title:
                  'No students linked to your account yet. Ask the academy '
                  'admin to link you.',
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
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (students.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: SegmentedButton<String>(
                      segments: [
                        for (final s in students)
                          ButtonSegment<String>(
                            value: s.id,
                            label: Text(s.firstName),
                          ),
                      ],
                      selected: {selected.id},
                      onSelectionChanged: (sel) =>
                          setState(() => _selectedStudentId = sel.first),
                    ),
                  ),
                _StudentHeader(student: selected),
                const SizedBox(height: AppSpacing.md),
                _UpcomingSessionsCard(studentId: selected.id),
                const SizedBox(height: AppSpacing.md),
                _BatchesCard(studentId: selected.id),
                const SizedBox(height: AppSpacing.md),
                _AttendanceCard(studentId: selected.id),
                const SizedBox(height: AppSpacing.md),
                _PerformanceCard(studentId: selected.id),
                const SizedBox(height: AppSpacing.md),
                _MediaGalleryCard(studentId: selected.id),
                const SizedBox(height: AppSpacing.md),
                _OutstandingCard(studentId: selected.id),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: AppListTile(
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: const Text('Events'),
                    subtitle: const Text('Browse + register for tournaments'),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const EventsPage()),
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

class _StudentHeader extends ConsumerWidget {
  const _StudentHeader({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: student.sportId)),
    );
    final photoUrl = ref
        .watch(storageServiceProvider)
        .publicAvatarUrl(student.photo);
    return AppCard(
      child: Row(
        children: [
          _AvatarCircle(
            size: 56,
            url: photoUrl,
            fallback: student.firstName.isEmpty ? '?' : student.firstName[0],
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${student.firstName} ${student.lastName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (sportLabel != '—')
                  Text(
                    sportLabel,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
        ],
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

class _UpcomingSessionsCard extends ConsumerWidget {
  const _UpcomingSessionsCard({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentUpcomingSessionsProvider(studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upcoming sessions — next 7 days',
            style: Theme.of(context).textTheme.titleMedium,
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
                return const Text('No sessions scheduled this week');
              }
              return Column(
                children: [
                  for (final s in sessions)
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
    final async = ref.watch(myLinkedStudentBatchesProvider(studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Batches', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(friendlyError(e)),
            data: (rows) {
              if (rows.isEmpty) return const Text('No active batches');
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 24),
                    _BatchRow(row: rows[i]),
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

class _BatchRow extends ConsumerWidget {
  const _BatchRow({required this.row});
  final StudentBatchRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.schedule, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(row.scheduleSummary)),
          ],
        ),
        if (coachName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarCircle(
                size: 36,
                url: coachPhotoUrl,
                fallback: coachName.isEmpty ? '?' : coachName[0],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Coach $coachName',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (row.coachQualifications.isNotEmpty)
                      Text(
                        row.coachQualifications.join(', '),
                        style: Theme.of(context).textTheme.bodySmall,
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
    final async = ref.watch(studentAttendanceProvider(studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance — last 60 days',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(friendlyError(e)),
            data: (days) {
              if (days.isEmpty) return const Text('No records yet');
              final total = days.length;
              final present = days.where((d) => d.status == 'present').length;
              final pct = (present * 100 / total).toStringAsFixed(0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final d in days)
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: _color(context, d.status),
                            borderRadius: BorderRadius.circular(2),
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
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              entry.$2,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('$present / $total present ($pct%)'),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Weekly % (last 4 weeks)',
                    style: Theme.of(context).textTheme.bodySmall,
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
    final async = ref.watch(studentAttendanceWeeklyProvider(studentId));
    return async.when(
      loading: () =>
          const SizedBox(height: 40, child: LinearProgressIndicator()),
      error: (e, _) => Text(friendlyError(e)),
      data: (weeks) {
        if (weeks.every((w) => w.total == 0)) {
          return const Text('Not enough data');
        }
        final primary = Theme.of(context).colorScheme.primary;
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
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Theme.of(context).dividerColor,
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
                      style: Theme.of(context).textTheme.labelSmall,
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
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${ws.day}/${ws.month}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, __, ___) {
                    final w = weeks[group.x];
                    return BarTooltipItem(
                      'Week of ${w.weekStart.day}/${w.weekStart.month}\n'
                      '${w.present}/${w.total}'
                      ' (${w.pct.toStringAsFixed(0)}%)',
                      const TextStyle(color: Colors.white),
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
    final async = ref.watch(studentPerformanceProvider(studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance trend',
            style: Theme.of(context).textTheme.titleMedium,
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
                return const Text('No assessments yet');
              }
              final primary = Theme.of(context).colorScheme.primary;
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
                        color: Theme.of(context).dividerColor,
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
                            style: Theme.of(context).textTheme.labelSmall,
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
                            const TextStyle(color: Colors.white),
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
    final async = ref.watch(mediaForStudentProvider(studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Photos & videos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(friendlyError(e)),
            data: (media) {
              if (media.isEmpty) {
                return Text(
                  'No photos or videos shared yet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        ],
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
        error: (_, __) => Container(
          color: fill,
          child: const Icon(Icons.broken_image_outlined),
        ),
        data: (url) => CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => ColoredBox(color: fill),
          errorWidget: (_, __, ___) => Container(
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

class _OutstandingCard extends ConsumerWidget {
  const _OutstandingCard({required this.studentId});
  final String studentId;

  Future<void> _payInvoice(
    BuildContext context,
    WidgetRef ref,
    String invoiceId,
  ) async {
    final client = ref.read(supabaseClientProvider);
    final profile = ref.read(currentProfileProvider).valueOrNull;
    final academy = ref.read(myAcademyProvider).valueOrNull;
    final checkout = RazorpayCheckout(client);
    try {
      final result = await checkout.payInvoice(
        invoiceId: invoiceId,
        academyName: academy?.name ?? 'PlayHub',
        prefillEmail: profile?.email,
        prefillContact: profile?.phone,
      );
      if (!context.mounted) return;
      switch (result) {
        case CheckoutSuccess():
          AppSnackbar.success(context, 'Payment received');
          // Webhook will update the invoice; refresh the dues list so the
          // row drops out without waiting for the user to pull-to-refresh.
          ref.invalidate(studentOutstandingDuesProvider(studentId));
        case CheckoutExternalWallet(:final walletName):
          AppSnackbar.info(context, 'Continuing in $walletName…');
        case CheckoutFailure(:final message):
          AppSnackbar.error(context, 'Payment failed: $message');
      }
    } on Object catch (e) {
      if (context.mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentOutstandingDuesProvider(studentId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Outstanding dues',
            style: Theme.of(context).textTheme.titleMedium,
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
                return const Text('Nothing due 🎉');
              }
              return Column(
                children: [
                  for (final r in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.invoiceNumber),
                      subtitle: Text(
                        'Due ${r.dueDate.year}-'
                        '${r.dueDate.month.toString().padLeft(2, '0')}-'
                        '${r.dueDate.day.toString().padLeft(2, '0')}'
                        '  •  ${r.status}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${r.balance.toStringAsFixed(0)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          FilledButton.tonal(
                            onPressed: () =>
                                _payInvoice(context, ref, r.invoiceId),
                            child: const Text('Pay'),
                          ),
                        ],
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
