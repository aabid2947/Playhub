import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_form_page.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_page.dart';
import 'package:playhub/features/inventory/presentation/vendors_page.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
      loading: () => const AppSkeletonList(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(inventoryItemsProvider),
      ),
      data: (items) {
        final list = showOnlyLow
            ? items.where((i) => i.lowStock).toList()
            : items;
        if (list.isEmpty) {
          return showOnlyLow
              ? const AppEmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'Nothing low',
                  subtitle: 'All items are above their reorder threshold.',
                )
              : const AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No items yet',
                  subtitle: 'Add equipment to start tracking stock.',
                );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(inventoryItemsProvider),
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _ItemRow(item: list[i]),
          ),
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
    return AppListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(item.name),
      subtitle: Text(
        [
          if (item.sku != null && item.sku!.isNotEmpty) item.sku!,
          '${item.onHand.toStringAsFixed(item.onHand.truncateToDouble() == item.onHand ? 0 : 2)} ${item.unit}',
          if (item.lowStock) 'Reorder ≥ ${item.reorderThreshold}',
        ].join(' · '),
      ),
      trailing: item.lowStock
          ? const AppBadge(text: 'Low stock', tone: AppBadgeTone.warning)
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InventoryItemPage(itemId: item.id),
        ),
      ),
    );
  }
}
