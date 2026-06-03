import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_form_page.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_page.dart';
import 'package:playhub/features/inventory/presentation/vendors_page.dart';
import 'package:playhub/core/error_messages.dart';

/// Three-tab landing for inventory: All, Low stock, Vendors.
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'All items'),
            Tab(text: 'Low stock'),
            Tab(text: 'Vendors'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(inventoryItemsProvider);
              ref.invalidate(vendorsProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () {
          if (_tabs.index == 2) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const VendorsPage()),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const InventoryItemFormPage(),
              ),
            );
          }
        },
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ItemsList(showOnlyLow: false),
          _ItemsList(showOnlyLow: true),
          VendorsPage(),
        ],
      ),
    );
  }
}

class _ItemsList extends ConsumerWidget {
  const _ItemsList({required this.showOnlyLow});
  final bool showOnlyLow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inventoryItemsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (items) {
        final list = showOnlyLow
            ? items.where((i) => i.lowStock).toList()
            : items;
        if (list.isEmpty) {
          return Center(
            child: Text(showOnlyLow ? 'Nothing low' : 'No items yet'),
          );
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _ItemRow(item: list[i]),
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: item.lowStock
            ? Theme.of(context).colorScheme.errorContainer
            : null,
        child: const Icon(Icons.inventory_2_outlined),
      ),
      title: Text(item.name),
      subtitle: Text(
        [
          if (item.sku != null && item.sku!.isNotEmpty) item.sku!,
          '${item.onHand.toStringAsFixed(item.onHand.truncateToDouble() == item.onHand ? 0 : 2)} ${item.unit}',
          if (item.lowStock) 'Reorder ≥ ${item.reorderThreshold}',
        ].join(' · '),
      ),
      trailing: item.lowStock
          ? Icon(Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error)
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InventoryItemPage(itemId: item.id),
        ),
      ),
    );
  }
}
