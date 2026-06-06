import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/chat/presentation/message_parent_button.dart';
import 'package:playhub/features/parent/data/parent_providers.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/performance/presentation/performance_history_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Read-only student summary page for the coach context. Avoids the
/// admin-only sections of StudentFormPage (fees, discounts, documents).
/// Coaches see basic profile, attendance summary, and a path into
/// performance history (where they can record new assessments).
class CoachStudentPage extends ConsumerWidget {
  const CoachStudentPage({required this.student, super.key});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(student.fullName),
        actions: [MessageParentButton(studentId: student.id)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _ProfileHeader(student: student),
          const SizedBox(height: AppSpacing.lg),
          const AppSectionHeader(title: 'Attendance'),
          _AttendanceSummary(studentId: student.id),
          const SizedBox(height: AppSpacing.lg),
          const AppSectionHeader(title: 'Performance'),
          AppCard(
            padding: EdgeInsets.zero,
            child: AppListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Performance assessments'),
              subtitle:
                  const Text('View history or record a new assessment'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => PerformanceHistoryPage(student: student),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _StudentMediaSection(student: student),
        ],
      ),
    );
  }
}

/// Identity card: avatar + name + sport/skill badges, then a divided block of
/// tappable contact rows (parent + student phone/email) that launch the dialer
/// or mail client.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.student});
  final Student student;

  String get _initials {
    final f = student.firstName.trim();
    final l = student.lastName.trim();
    final a = f.isEmpty ? '' : f[0];
    final b = l.isEmpty ? '' : l[0];
    final combined = '$a$b'.toUpperCase();
    return combined.isEmpty ? '?' : combined;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sportLabel = ref.watch(sportDisplayProvider((
      sportId: student.sportId,
    )));

    final badges = <Widget>[
      if (sportLabel != '—') AppBadge(text: sportLabel),
      if (student.skillLevel != null)
        AppBadge(text: student.skillLevel!, tone: AppBadgeTone.info),
    ];

    final contacts = <Widget>[
      if (student.parentPhone != null)
        _ContactRow(
          icon: Icons.phone_outlined,
          label: student.parentName.isEmpty
              ? 'Parent phone'
              : '${student.parentName} (parent)',
          value: student.parentPhone!,
          scheme: 'tel',
        ),
      if (student.parentEmail != null)
        _ContactRow(
          icon: Icons.mail_outline,
          label: 'Parent email',
          value: student.parentEmail!,
          scheme: 'mailto',
        ),
      if (student.phone != null)
        _ContactRow(
          icon: Icons.phone_outlined,
          label: 'Student phone',
          value: student.phone!,
          scheme: 'tel',
        ),
      if (student.email != null)
        _ContactRow(
          icon: Icons.mail_outline,
          label: 'Student email',
          value: student.email!,
          scheme: 'mailto',
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(
                  _initials,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: AppType.semibold,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: badges,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (contacts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.xs),
            ...contacts,
          ] else if (student.parentName.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Parent: ${student.parentName}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// One tappable contact row: leading icon, a small label, the value as primary
/// text, and a trailing affordance hinting at the launch action. [scheme] is
/// `tel` or `mailto`.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.scheme,
  });

  final IconData icon;
  final String label;
  final String value;
  final String scheme;

  Future<void> _launch(BuildContext context) async {
    final uri = Uri(scheme: scheme, path: value.replaceAll(' ', ''));
    try {
      final ok = await launcher.launchUrl(uri);
      if (!ok && context.mounted) {
        AppSnackbar.error(context, 'Could not open this contact.');
      }
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final trailingIcon =
        this.scheme == 'tel' ? Icons.call_outlined : Icons.send_outlined;
    return InkWell(
      onTap: () => _launch(context),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(value, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            Icon(trailingIcon, size: 20, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// Attendance over the last 60 days as a metric callout, with a small trend
/// cue comparing the most recent week's rate to the prior weeks.
class _AttendanceSummary extends ConsumerWidget {
  const _AttendanceSummary({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final attendance = ref.watch(studentAttendanceProvider(studentId));

    return AppCard(
      child: attendance.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: AppSkeleton(width: 200, height: 28),
        ),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () =>
              ref.invalidate(studentAttendanceProvider(studentId)),
        ),
        data: (days) {
          if (days.isEmpty) {
            return Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'No attendance recorded in the last 60 days',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          }
          final present = days.where((d) => d.status == 'present').length;
          final pct = present * 100 / days.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last 60 days',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: AppType.bold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$present / ${days.length} present',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  _TrendCue(studentId: studentId),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A small up/down/flat trend chip comparing the latest tracked week's
/// attendance rate against the average of the prior weeks. Renders nothing
/// until there's enough history to be meaningful.
class _TrendCue extends ConsumerWidget {
  const _TrendCue({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    final weekly = ref.watch(studentAttendanceWeeklyProvider(studentId));

    return weekly.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (weeks) {
        final tracked = weeks.where((w) => w.total > 0).toList();
        if (tracked.length < 2) return const SizedBox.shrink();
        final latest = tracked.last.pct;
        final priors = tracked.sublist(0, tracked.length - 1);
        final priorAvg =
            priors.map((w) => w.pct).reduce((a, b) => a + b) / priors.length;
        final delta = latest - priorAvg;

        IconData icon;
        Color color;
        if (delta > 5) {
          icon = Icons.trending_up;
          color = semantics.success;
        } else if (delta < -5) {
          icon = Icons.trending_down;
          color = semantics.danger;
        } else {
          icon = Icons.trending_flat;
          color = theme.colorScheme.onSurfaceVariant;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: AppType.semibold,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "Photos & videos" for one student, flattened to a single section (header +
/// content) rather than a card-in-card. Coaches AND trainers can attach
/// standalone media here (no scored assessment) — it's shared straight to the
/// student and their parent. Insert is gated client-side by
/// `uploadStudentMedia` and authoritatively by `can_upload_student_media()`.
class _StudentMediaSection extends ConsumerStatefulWidget {
  const _StudentMediaSection({required this.student});
  final Student student;

  @override
  ConsumerState<_StudentMediaSection> createState() =>
      _StudentMediaSectionState();
}

class _StudentMediaSectionState extends ConsumerState<_StudentMediaSection> {
  bool _busy = false;

  Future<void> _add({required bool video}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final storage = ref.read(storageServiceProvider);
    try {
      final picked = video
          ? await storage.pickAndUploadStudentMediaVideo(
              academyId: widget.student.academyId,
              studentId: widget.student.id,
            )
          : await storage.pickAndUploadStudentMediaPhoto(
              academyId: widget.student.academyId,
              studentId: widget.student.id,
            );
      if (picked == null) return;
      await addStudentMedia(
        ref,
        studentId: widget.student.id,
        mediaType: video ? 'video' : 'photo',
        filePath: picked.path,
        originalFilename: picked.originalFilename,
        mimeType: picked.mimeType,
        sizeBytes: picked.sizeBytes,
      );
      if (mounted) {
        AppSnackbar.success(context, 'Shared with the student & parent');
      }
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(PerformanceMedia m) async {
    final storage = ref.read(storageServiceProvider);
    try {
      final url = await storage.signedPerformanceMediaUrl(m.filePath);
      final ok = await launcher.launchUrl(
        Uri.parse(url),
        mode: launcher.LaunchMode.externalApplication,
      );
      if (!ok && mounted) AppSnackbar.error(context, 'Could not open file.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canUpload = ref.watch(capabilitiesProvider).uploadStudentMedia;
    final mediaAsync = ref.watch(mediaForStudentProvider(widget.student.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: 'Photos & videos',
          trailing: mediaAsync.maybeWhen(
            orElse: () => null,
            data: (media) => media.isEmpty
                ? null
                : AppBadge(text: '${media.length}'),
          ),
        ),
        Text(
          'Visible to this student and their parent',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (canUpload) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Add photo'),
                onPressed: _busy ? null : () => _add(video: false),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Add video'),
                onPressed: _busy ? null : () => _add(video: true),
              ),
            ],
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: AppSpacing.sm),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: AppSpacing.md),
        mediaAsync.when(
          loading: () => const AppSkeleton(width: 140, height: 128),
          error: (e, _) => AppErrorView(
            message: friendlyError(e),
            onRetry: () =>
                ref.invalidate(mediaForStudentProvider(widget.student.id)),
          ),
          data: (media) {
            if (media.isEmpty) {
              return Text(
                canUpload
                    ? 'No photos or videos yet. Add the first one above.'
                    : 'No photos or videos have been shared yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              );
            }
            return SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: media.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (_, i) => _MediaThumb(
                  media: media[i],
                  onTap: () => _open(media[i]),
                ),
              ),
            );
          },
        ),
      ],
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
          const Center(child: Icon(Icons.play_circle_outline, size: 36)),
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
        child: SizedBox(width: 128, height: 128, child: inner),
      ),
    );
  }
}
