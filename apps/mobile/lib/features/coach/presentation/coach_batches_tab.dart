import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/presentation/batch_detail_page.dart';
import 'package:playhub/features/batches/presentation/batch_form_page.dart';
import 'package:playhub/features/chat/presentation/batch_chat_button.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class CoachBatchesTab extends ConsumerWidget {
  const CoachBatchesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myBatchesProvider);
    // head_coach can create batches (in their sport, enforced by RLS); plain
    // coach/trainer cannot — manageBatches is false for them.
    final canCreate = ref.watch(capabilitiesProvider).manageBatches;
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: 'fab-coach-batch',
              icon: const Icon(Icons.add),
              label: const Text('New batch'),
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const BatchFormPage()),
                );
                ref.invalidate(myBatchesProvider);
              },
            )
          : null,
      body: async.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(myBatchesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const AppEmptyState(
              icon: Icons.group_work_outlined,
              title: 'No batches yet',
              subtitle: 'Active batches assigned to you will appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myBatchesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _CoachBatchTile(batch: list[i]),
            ),
          );
        },
      ),
    );
  }
}

/// One batch row in the coach's list. The trailing area is a fixed-width slot
/// so the batch-chat button (which swaps an icon for a busy spinner) can't
/// jitter the chevron's position as its state changes.
class _CoachBatchTile extends ConsumerWidget {
  const _CoachBatchTile({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sportLabel = ref.watch(sportDisplayProvider((sportId: batch.sportId)));
    final subtitle = [
      batch.schedule.summary,
      if (sportLabel != '—') sportLabel,
    ].join('  •  ');

    return AppListTile(
      leading: const Icon(Icons.group_work_outlined),
      title: Text(batch.name),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BatchChatButton(batchId: batch.id, compact: true),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => BatchDetailPage(batch: batch)),
      ),
    );
  }
}
