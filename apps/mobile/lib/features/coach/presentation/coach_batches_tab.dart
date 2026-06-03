import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/batches/presentation/batch_detail_page.dart';
import 'package:playhub/features/chat/presentation/batch_chat_button.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/core/error_messages.dart';

class CoachBatchesTab extends ConsumerWidget {
  const CoachBatchesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myBatchesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My batches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myBatchesProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No active batches assigned to you yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = list[i];
              final sportLabel = ref.watch(sportDisplayProvider((
                sportId: b.sportId,
              )));
              return ListTile(
                leading: const Icon(Icons.group_work_outlined),
                title: Text(b.name),
                subtitle: Text(
                  '${b.schedule.summary}'
                  '${sportLabel != '—' ? '  •  $sportLabel' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BatchChatButton(batchId: b.id, compact: true),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                      builder: (_) => BatchDetailPage(batch: b)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
