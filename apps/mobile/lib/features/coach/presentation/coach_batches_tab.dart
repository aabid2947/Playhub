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

/// Coach batches list — v1 "Sports-Light", archetype B (list).
///
/// App-bar-less body under the CoachHomeShell AppBar: an in-body header row
/// (title + a live count [AppBadge]) sits above a column of sport-iconed batch
/// [AppCard]s. Tap a card → [BatchDetailPage]. The create FAB is gated on
/// [Capabilities.manageBatches] (true only for head_coach, who may create
/// batches in their own sport — RLS is the real gate; this just hides the entry
/// point for plain coach/trainer, who cannot).
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                // Leave room so the last card clears the FAB (when shown).
                AppSpacing.xxl + AppSpacing.xl,
              ),
              itemCount: list.length + 1,
              separatorBuilder: (_, i) => i == 0
                  ? const SizedBox.shrink()
                  : const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return _ListHeader(count: list.length);
                }
                return _CoachBatchCard(batch: list[i - 1]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// In-body header: a mixed-case navy section title with a live count badge —
/// gives the app-bar-less tab a titled top edge under the shell AppBar.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AppSectionHeader(
      title: 'My batches',
      icon: Icons.group_work_outlined,
      trailing: AppBadge(
        text: count == 1 ? '1 batch' : '$count batches',
        tone: AppBadgeTone.brand,
      ),
    );
  }
}

/// One batch row, v1 card. A sport-tinted leading icon tile → batch name → one
/// tight schedule · sport line → a trailing [BatchChatButton] (preserved) plus
/// an enrolment-count [AppBadge]. The trailing slot is a fixed [Row] so the
/// chat button swapping in a busy spinner can't jitter the count's position.
class _CoachBatchCard extends ConsumerWidget {
  const _CoachBatchCard({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sportLabel = ref.watch(sportDisplayProvider((sportId: batch.sportId)));
    final hasSport = sportLabel != '—';
    final tint = colorFromName(hasSport ? sportLabel : batch.name);
    final subtitle = [
      batch.schedule.summary,
      if (hasSport) sportLabel,
    ].join('  •  ');

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => BatchDetailPage(batch: batch)),
      ),
      child: AppListTile(
        wrapLeading: false,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            hasSport ? sportIcon(sportLabel) : Icons.group_work_outlined,
            color: tint,
            size: 20,
          ),
        ),
        title: Text(
          batch.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BatchChatButton(batchId: batch.id, compact: true),
            const SizedBox(width: AppSpacing.xs),
            AppBadge(
              text: '${batch.enrolledCount}',
              icon: Icons.people_alt_outlined,
            ),
          ],
        ),
      ),
    );
  }
}
