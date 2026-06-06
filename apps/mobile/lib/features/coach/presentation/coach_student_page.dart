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
    final attendance = ref.watch(studentAttendanceProvider(student.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(student.fullName),
        actions: [MessageParentButton(studentId: student.id)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.fullName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Builder(builder: (_) {
                  final sportLabel = ref.watch(sportDisplayProvider((
                    sportId: student.sportId,
                  )));
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (sportLabel != '—') AppBadge(text: sportLabel),
                      if (student.skillLevel != null)
                        AppBadge(
                          text: student.skillLevel!,
                          tone: AppBadgeTone.info,
                        ),
                    ],
                  );
                }),
                if (student.parentName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Parent: ${student.parentName}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (student.parentPhone != null)
                  Text('Phone: ${student.parentPhone}',
                      style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Attendance — last 60 days',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                attendance.when(
                  loading: () => const AppSkeleton(width: 180),
                  error: (e, _) => Text(
                    friendlyError(e),
                    style:
                        TextStyle(color: AppSemanticColors.of(context).danger),
                  ),
                  data: (days) {
                    if (days.isEmpty) {
                      return Text(
                        'No records yet',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      );
                    }
                    final present =
                        days.where((d) => d.status == 'present').length;
                    final pct =
                        (present * 100 / days.length).toStringAsFixed(0);
                    return Text('$present / ${days.length} present ($pct%)');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.md),
          _StudentMediaCard(student: student),
        ],
      ),
    );
  }
}

/// "Photos & videos" for one student. Coaches AND trainers can attach
/// standalone media here (no scored assessment) — it's shared straight to the
/// student and their parent. Insert is gated client-side by
/// `uploadStudentMedia` and authoritatively by `can_upload_student_media()`.
class _StudentMediaCard extends ConsumerStatefulWidget {
  const _StudentMediaCard({required this.student});
  final Student student;

  @override
  ConsumerState<_StudentMediaCard> createState() => _StudentMediaCardState();
}

class _StudentMediaCardState extends ConsumerState<_StudentMediaCard> {
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
    final canUpload = ref.watch(capabilitiesProvider).uploadStudentMedia;
    final mediaAsync = ref.watch(mediaForStudentProvider(widget.student.id));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Photos & videos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Visible to this student and their parent',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (canUpload)
            Wrap(
              spacing: AppSpacing.sm,
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
          if (_busy) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: AppSpacing.sm),
          mediaAsync.when(
            loading: () => const AppSkeleton(width: 120),
            error: (e, _) => Text(friendlyError(e)),
            data: (media) {
              if (media.isEmpty) {
                return Text(
                  'No photos or videos yet',
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
                    onTap: () => _open(media[i]),
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
