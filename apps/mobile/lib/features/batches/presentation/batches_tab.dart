import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/batch_detail_page.dart';
import 'package:playhub/features/batches/presentation/batch_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';

class BatchesTab extends ConsumerStatefulWidget {
  const BatchesTab({super.key});

  @override
  ConsumerState<BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends ConsumerState<BatchesTab> {
  String? _sportFilter;

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(batchesProvider);

    return Scaffold(
      body: Column(
        children: [
          SportFilterChipBar(
            selectedId: _sportFilter,
            onSelected: (id) => setState(() => _sportFilter = id),
          ),
          Expanded(
            child: batchesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (batches) {
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
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _BatchTile(batch: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const BatchFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New batch'),
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
    final utilLabel = cap == null
        ? '${batch.enrolledCount}'
        : '${batch.enrolledCount}/$cap';
    final sportLabel = ref.watch(sportDisplayProvider((
      sportId: batch.sportId,
    )));

    return ListTile(
      leading: const Icon(Icons.schedule_outlined),
      title: Text(batch.name),
      subtitle: Text(
        [
          batch.schedule.summary,
          if (sportLabel != '—') sportLabel,
          if (batch.skillLevel != null) batch.skillLevel!,
        ].join(' • '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(utilLabel,
              style: Theme.of(context).textTheme.titleMedium),
          Text('enrolled',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BatchDetailPage(batch: batch),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No batches yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "New batch" to schedule your first session.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
