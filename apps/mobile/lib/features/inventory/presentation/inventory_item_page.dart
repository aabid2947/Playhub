import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_form_page.dart';
import 'package:playhub/features/inventory/presentation/movement_sheet.dart';

class InventoryItemPage extends ConsumerWidget {
  const InventoryItemPage({required this.itemId, super.key});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(inventoryItemsProvider).valueOrNull ?? const [];
    final item = items.where((i) => i.id == itemId).firstOrNull;
    final movesAsync = ref.watch(itemMovementsProvider(itemId));

    if (item == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final df = DateFormat('dd MMM yyyy · HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InventoryItemFormPage(existing: item),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.swap_vert),
        label: const Text('Movement'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => MovementSheet(item: item),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StockCard(item: item),
          const SizedBox(height: 12),
          Text('Recent movements',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          movesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (moves) {
              if (moves.isEmpty) {
                return const Text('No movements logged yet.');
              }
              return Column(
                children: [
                  for (final m in moves)
                    ListTile(
                      leading: CircleAvatar(
                        child: Icon(_iconFor(m.kind)),
                      ),
                      title: Text(
                        '${m.kind.toUpperCase()} · ${m.qty.toStringAsFixed(m.qty.truncateToDouble() == m.qty ? 0 : 2)}',
                      ),
                      subtitle: Text([
                        df.format(m.performedAt),
                        if (m.reference != null && m.reference!.isNotEmpty)
                          'ref: ${m.reference}',
                        if (m.notes != null && m.notes!.isNotEmpty) m.notes!,
                      ].join(' · ')),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'in':
        return Icons.add_circle_outline;
      case 'out':
        return Icons.remove_circle_outline;
      case 'return':
        return Icons.assignment_returned_outlined;
      case 'adjustment':
        return Icons.tune_outlined;
    }
    return Icons.swap_vert;
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.sku != null && item.sku!.isNotEmpty)
              Text('SKU: ${item.sku}',
                  style: Theme.of(context).textTheme.bodySmall),
            Text(
              '${item.onHand.toStringAsFixed(item.onHand.truncateToDouble() == item.onHand ? 0 : 2)} ${item.unit}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            if (item.reorderThreshold > 0)
              Text(
                'Reorder threshold: ${item.reorderThreshold}',
                style: TextStyle(
                  color: item.lowStock
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            if (item.unitCost > 0)
              Text('Unit cost: ₹${item.unitCost.toStringAsFixed(2)}'),
            if (item.description != null && item.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.description!),
            ],
          ],
        ),
      ),
    );
  }
}
