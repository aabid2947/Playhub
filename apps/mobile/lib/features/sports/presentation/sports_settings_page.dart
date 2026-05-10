import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/sports/data/sport.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';

/// Settings → Sports. Pick a center, manage which sports it offers.
/// Defaults to the user's center_id when set; falls back to the first
/// center in the academy.
class SportsSettingsPage extends ConsumerStatefulWidget {
  const SportsSettingsPage({super.key});

  @override
  ConsumerState<SportsSettingsPage> createState() =>
      _SportsSettingsPageState();
}

class _SportsSettingsPageState extends ConsumerState<SportsSettingsPage> {
  String? _centerId;

  @override
  Widget build(BuildContext context) {
    final centersAsync = ref.watch(centersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_centerId != null) {
                ref.invalidate(centerSportsProvider(_centerId!));
              }
              ref.invalidate(academyCenterSportsProvider);
            },
          ),
        ],
      ),
      body: centersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (centers) {
          if (centers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No centers yet — add a center in Settings → Centers '
                  'first, then come back here to enable its sports.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          _centerId ??= centers.first.id;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  initialValue: _centerId,
                  decoration: const InputDecoration(labelText: 'Center'),
                  items: [
                    for (final c in centers.where((c) => c.isActive))
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _centerId = v),
                ),
              ),
              Expanded(
                child: _centerId == null
                    ? const SizedBox.shrink()
                    : _CenterSportsList(centerId: _centerId!),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _centerId == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add sport'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _AddSportSheet(centerId: _centerId!),
              ),
            ),
    );
  }
}

class _CenterSportsList extends ConsumerWidget {
  const _CenterSportsList({required this.centerId});
  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(centerSportsProvider(centerId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No sports for this center. Tap "Add sport" to enable one.',
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
    );
  }
}

class _SportRow extends ConsumerWidget {
  const _SportRow({required this.row});
  final CenterSport row;

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
              await repo.disableCenterSport(row.id);
              ref.invalidate(centerSportsProvider(row.centerId));
              ref.invalidate(academyCenterSportsProvider);
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
    CenterSport row,
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
    await repo.updateCenterSport(
      row.id,
      customName: result.isEmpty ? '' : result,
    );
    ref.invalidate(centerSportsProvider(row.centerId));
    ref.invalidate(academyCenterSportsProvider);
  }
}

class _AddSportSheet extends ConsumerWidget {
  const _AddSportSheet({required this.centerId});
  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAsync = ref.watch(allSportsProvider);
    final enabledAsync = ref.watch(centerSportsProvider(centerId));

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
                    child: Text(
                      'Every catalog sport is already enabled at this center.',
                    ),
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
                            await repo.enableSportAtCenter(
                              centerId: centerId,
                              sportId: s.id,
                            );
                            ref.invalidate(centerSportsProvider(centerId));
                            ref.invalidate(academyCenterSportsProvider);
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
