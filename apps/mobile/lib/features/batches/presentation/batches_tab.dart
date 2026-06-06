import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/batch_detail_page.dart';
import 'package:playhub/features/batches/presentation/batch_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class BatchesTab extends ConsumerStatefulWidget {
  const BatchesTab({super.key});

  @override
  ConsumerState<BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends ConsumerState<BatchesTab> {
  String? _sportFilter;

  void _openForm() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const BatchFormPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(batchesProvider);
    final caps = ref.watch(capabilitiesProvider);

    return Scaffold(
      body: Column(
        children: [
          // The sport chip bar is the single, unified filter for this list —
          // batches only filter on sport, so the chip bar *is* the filter row
          // (mirrors the students/coaches unified-filter pattern).
          SportFilterChipBar(
            selectedId: _sportFilter,
            onSelected: (id) => setState(() => _sportFilter = id),
          ),
          Expanded(
            child: batchesAsync.when(
              loading: () => const AppSkeletonList(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(batchesProvider),
              ),
              data: (batches) {
                // Client-side sport filter (RLS already scopes by academy).
                final list = _sportFilter == null
                    ? batches
                    : batches
                        .where((b) => b.sportId == _sportFilter)
                        .toList();
                if (list.isEmpty) {
                  return const _EmptyState();
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(batchesProvider),
                  child: ListView.separated(
                    itemCount: list.length + 1,
                    separatorBuilder: (_, i) => i == 0
                        ? const SizedBox.shrink()
                        : const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _ResultCount(count: list.length);
                      }
                      return _BatchTile(batch: list[i - 1]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: caps.manageBatches
          ? FloatingActionButton.extended(
              heroTag: 'fab-batches',
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('New batch'),
            )
          : null,
    );
  }
}

/// Visible result count above the list, e.g. "12 batches".
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        count == 1 ? '1 batch' : '$count batches',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BatchTile extends ConsumerWidget {
  const _BatchTile({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = batch.capacity;
    final capacityLabel = cap == null
        ? '${batch.enrolledCount}'
        : '${batch.enrolledCount}/$cap';
    // Tone the capacity pill by fullness so a full/over-capacity batch reads at
    // a glance; neutral when there's no cap to measure against.
    final capacityTone = cap == null
        ? AppBadgeTone.neutral
        : batch.enrolledCount >= cap
            ? AppBadgeTone.warning
            : AppBadgeTone.brand;

    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: batch.sportId)),
    );
    // One tight subtitle line: schedule, then sport, then skill level.
    final facts = <String>[
      batch.schedule.summary,
      if (sportLabel != '—') sportLabel,
      if (batch.skillLevel != null) batch.skillLevel!,
    ];

    return AppListTile(
      leading: const Icon(Icons.schedule_outlined),
      title: Text(batch.name),
      subtitle: Text(
        facts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!batch.isActive) ...[
            const AppBadge(text: 'Archived'),
            const SizedBox(width: AppSpacing.xs),
          ],
          AppBadge(text: capacityLabel, tone: capacityTone),
        ],
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => BatchDetailPage(batch: batch)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.schedule_outlined,
      title: 'No batches yet',
      subtitle: 'Tap "New batch" to schedule your first session.',
    );
  }
}
