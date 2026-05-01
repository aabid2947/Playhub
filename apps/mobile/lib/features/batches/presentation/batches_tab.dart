import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/batch_detail_page.dart';
import 'package:playhub/features/batches/presentation/batch_form_page.dart';

class BatchesTab extends ConsumerWidget {
  const BatchesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batchesAsync = ref.watch(batchesProvider);

    return Scaffold(
      body: batchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (batches) {
          if (batches.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(batchesProvider),
            child: ListView.separated(
              itemCount: batches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _BatchTile(batch: batches[i]),
            ),
          );
        },
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

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final cap = batch.capacity;
    final utilLabel = cap == null
        ? '${batch.enrolledCount}'
        : '${batch.enrolledCount}/$cap';

    return ListTile(
      leading: const Icon(Icons.schedule_outlined),
      title: Text(batch.name),
      subtitle: Text(
        [
          batch.schedule.summary,
          if (batch.sport != null) batch.sport,
          if (batch.skillLevel != null) batch.skillLevel,
        ].whereType<String>().join(' • '),
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
