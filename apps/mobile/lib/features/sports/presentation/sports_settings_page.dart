import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/sports/data/sport.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';

/// Settings → Sports. Lists the academy's enabled sports, lets owner/admin
/// add new ones from the global catalog, rename them locally, or remove.
class SportsSettingsPage extends ConsumerWidget {
  const SportsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(academySportsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(academySportsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add sport'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _AddSportSheet(),
        ),
      ),
      body: enabledAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No sports yet. Tap "Add sport" to enable the ones your '
                  'academy offers.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _SportRow(row: rows[i]),
          );
        },
      ),
    );
  }
}

class _SportRow extends ConsumerWidget {
  const _SportRow({required this.row});
  final AcademySport row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.sports_outlined)),
      title: Text(row.displayName),
      subtitle: Text(row.customName != null && row.customName!.isNotEmpty
          ? 'Renamed from ${row.sport.name}'
          : row.sport.category ?? ''),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          final repo = await ref.read(sportsRepoProvider.future);
          if (repo == null) return;
          if (v == 'rename') {
            if (!context.mounted) return;
            await _renameDialog(context, ref, row);
          } else if (v == 'remove') {
            if (!context.mounted) return;
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Remove ${row.displayName}?'),
                content: const Text(
                  'Existing students / batches keep their sport assignment '
                  'until you change them. You can re-add this sport later.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            );
            if (confirm ?? false) {
              await repo.disableAcademySport(row.id);
              ref.invalidate(academySportsProvider);
            }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }

  Future<void> _renameDialog(
    BuildContext context,
    WidgetRef ref,
    AcademySport row,
  ) async {
    final ctrl = TextEditingController(text: row.customName ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename ${row.sport.name}'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: row.sport.name,
            helperText: 'Leave blank to revert to the catalog name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final repo = await ref.read(sportsRepoProvider.future);
    if (repo == null) return;
    await repo.updateAcademySport(
      row.id,
      customName: result.isEmpty ? '' : result,
    );
    ref.invalidate(academySportsProvider);
  }
}

class _AddSportSheet extends ConsumerWidget {
  const _AddSportSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAsync = ref.watch(allSportsProvider);
    final enabledAsync = ref.watch(academySportsProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a sport',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            allAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (all) {
                final enabledIds = (enabledAsync.valueOrNull ?? const [])
                    .map((s) => s.sport.id)
                    .toSet();
                final candidates =
                    all.where((s) => !enabledIds.contains(s.id)).toList();
                if (candidates.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Every catalog sport is already enabled.'),
                  );
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = candidates[i];
                      return ListTile(
                        title: Text(s.name),
                        subtitle:
                            s.category != null ? Text(s.category!) : null,
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            final repo =
                                await ref.read(sportsRepoProvider.future);
                            if (repo == null) return;
                            await repo.enableSport(s.id);
                            ref.invalidate(academySportsProvider);
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('Add'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
