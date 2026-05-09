import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
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
        padding: const EdgeInsets.all(16),
        children: [
          if (assessment.overallScore != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
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
            ),
          const SizedBox(height: 12),
          Text('Skills', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          skillsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (skills) => Card(
              child: Column(
                children: [
                  for (final s in skills)
                    ListTile(
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
            const SizedBox(height: 12),
            Text('Feedback', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(assessment.qualitativeFeedback!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('Evidence', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          mediaAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('Error: $e'),
            data: (media) {
              if (media.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No photos or videos attached.'),
                  ),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (final m in media)
                      ListTile(
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file.')),
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open failed: $e')),
        );
      }
    }
  }
}
