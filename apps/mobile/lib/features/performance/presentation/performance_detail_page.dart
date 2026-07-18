import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

class PerformanceDetailPage extends ConsumerWidget {
  const PerformanceDetailPage({required this.assessment, super.key});

  final PerformanceAssessment assessment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(skillsForAssessmentProvider(assessment.id));
    final mediaAsync = ref.watch(mediaForAssessmentProvider(assessment.id));
    final sportLabel = ref.watch(sportDisplayProvider((
      sportId: assessment.sportId,
    )));
    final dateStr = assessment.assessmentDate.toIso8601String().substring(0, 10);
    final sportName = sportLabel == '—' ? 'General' : sportLabel;

    return Scaffold(
      appBar: AppBar(title: Text('$sportName · $dateStr')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Header callout: the overall score is the prominent headline metric,
          // with sport + assessment date as the supporting facts. Rendered even
          // when unscored so the date always has a home in the body.
          _ScoreCallout(
            score: assessment.overallScore,
            sportName: sportName,
            dateStr: dateStr,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppSectionHeader(
            title: 'Skills',
            icon: Icons.insights_outlined,
            trailing: skillsAsync.maybeWhen(
              data: (skills) => _CountLabel(count: skills.length),
              orElse: () => null,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          skillsAsync.when(
            loading: () => const AppLoading(),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () =>
                  ref.invalidate(skillsForAssessmentProvider(assessment.id)),
            ),
            data: (skills) {
              if (skills.isEmpty) {
                return const _InfoCard(text: 'No skills were scored.');
              }
              // Each skill renders as a labeled 0..10 meter so the spread of
              // strengths/weaknesses reads at a glance; notes hang below.
              return AppCard(
                child: Column(
                  children: [
                    for (var i = 0; i < skills.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.lg),
                      _SkillRow(skill: skills[i]),
                    ],
                  ],
                ),
              );
            },
          ),
          if (assessment.qualitativeFeedback != null &&
              assessment.qualitativeFeedback!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Feedback'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              child: Text(
                assessment.qualitativeFeedback!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppSectionHeader(
            title: 'Evidence',
            trailing: mediaAsync.maybeWhen(
              data: (media) =>
                  media.isEmpty ? null : _CountLabel(count: media.length),
              orElse: () => null,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          mediaAsync.when(
            loading: () => const AppLoading(),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () =>
                  ref.invalidate(mediaForAssessmentProvider(assessment.id)),
            ),
            data: (media) {
              if (media.isEmpty) {
                return const _InfoCard(text: 'No photos or videos attached.');
              }
              return AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < media.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _MediaRow(
                        media: media[i],
                        onOpen: () => _open(context, ref, media[i]),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

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
}

/// Header callout for the assessment: the overall score is the headline value,
/// with the sport and assessment date as supporting facts. Stays present (and
/// reads "Not scored") when no overall score was recorded.
class _ScoreCallout extends StatelessWidget {
  const _ScoreCallout({
    required this.score,
    required this.sportName,
    required this.dateStr,
  });

  final double? score;
  final String sportName;
  final String dateStr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scored = score != null;
    final mutedSmall = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prominent overall-score metric.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall score',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  scored ? score!.toStringAsFixed(2) : 'Not scored',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: scored ? null : scheme.onSurfaceVariant,
                  ),
                ),
                if (scored) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('out of 10', style: mutedSmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          // Supporting context: sport + assessment date.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppBadge(text: sportName, tone: AppBadgeTone.brand),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(dateStr, style: mutedSmall),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One skill line: a labeled 0..10 meter (`AppLabeledProgress`) with the score
/// as its trailing value, and any coach notes hung beneath in muted text. The
/// bar takes a deterministic sport-style accent per skill name so the breakdown
/// reads as a colorful spread rather than a wall of identical bars.
class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill});
  final PerformanceSkill skill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = skill.notes;
    final hasNotes = notes != null && notes.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppLabeledProgress(
          label: skill.skillName,
          value: skill.score / 10,
          trailing: '${skill.score}/10',
          color: colorFromName(skill.skillName),
        ),
        if (hasNotes) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            notes,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// One evidence row: a tinted type icon, a friendly filename, a type +
/// size metadata line, and an explicit "Open" affordance.
class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.media, required this.onOpen});
  final PerformanceMedia media;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isVideo = media.mediaType == 'video';
    final name = media.originalFilename ?? _basename(media.filePath);
    final meta = [
      if (media.sizeBytes != null) _formatBytes(media.sizeBytes!),
      if (media.mimeType != null) media.mimeType!,
    ].join(' · ');

    return AppListTile(
      leading: Icon(
        isVideo ? Icons.videocam_outlined : Icons.photo_outlined,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          AppBadge(
            text: isVideo ? 'Video' : 'Photo',
            tone: AppBadgeTone.info,
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: 'Open',
        onPressed: onOpen,
      ),
      onTap: onOpen,
    );
  }

  String _basename(String path) {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Small count chip used as an `AppSectionHeader` trailing affordance.
class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '$count',
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Muted inline card for a section that has no rows yet.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
