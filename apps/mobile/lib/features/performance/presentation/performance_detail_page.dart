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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${sportLabel == '—' ? 'general' : sportLabel} · '
          '${assessment.assessmentDate.toIso8601String().substring(0, 10)}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (assessment.overallScore != null) ...[
            AppCard(
              child: Row(
                children: [
                  Text('Overall score',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    assessment.overallScore!.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const AppSectionHeader(title: 'Skills'),
          const SizedBox(height: AppSpacing.sm),
          skillsAsync.when(
            loading: () => const AppLoading(),
            error: (e, _) => Text(
              friendlyError(e),
              style: TextStyle(color: AppSemanticColors.of(context).danger),
            ),
            data: (skills) => AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final s in skills)
                    AppListTile(
                      title: Text(s.skillName),
                      trailing: Text(
                        '${s.score}/10',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: s.notes == null ? null : Text(s.notes!),
                    ),
                ],
              ),
            ),
          ),
          if (assessment.qualitativeFeedback != null &&
              assessment.qualitativeFeedback!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Feedback'),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Text(
                assessment.qualitativeFeedback!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'Evidence'),
          const SizedBox(height: AppSpacing.sm),
          mediaAsync.when(
            loading: () => const AppLoading(),
            error: (e, _) => Text(
              friendlyError(e),
              style: TextStyle(color: AppSemanticColors.of(context).danger),
            ),
            data: (media) {
              if (media.isEmpty) {
                return AppCard(
                  child: Text(
                    'No photos or videos attached.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                );
              }
              return AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final m in media)
                      AppListTile(
                        leading: Icon(
                          m.mediaType == 'video'
                              ? Icons.videocam_outlined
                              : Icons.photo_outlined,
                        ),
                        title: Text(m.originalFilename ?? m.filePath),
                        subtitle: Text(
                          m.mimeType ?? m.mediaType,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => _open(context, ref, m),
                      ),
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
