import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_form_page.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_page.dart';
import 'package:playhub/features/inventory/presentation/vendors_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Three-tab landing for inventory: All, Low stock, Vendors. Pushed page, so it
/// keeps its own AppBar + TabBar; the body lists follow the v1 list archetype
/// (in-body count badge → AppCard tiles with a tinted icon + low-stock badge).
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTabChanged);

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  // Rebuild so the FAB label/action tracks the active tab.
  void _onTabChanged() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  bool get _isVendorsTab => _tabs.index == 2;

  void _onCreate() {
    if (_isVendorsTab) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VendorsPage()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const InventoryItemFormPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider);
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
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(inventoryItemsProvider);
              ref.invalidate(vendorsProvider);
            },
          ),
        ],
      ),
      floatingActionButton: caps.manageInventory
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(_isVendorsTab ? 'New vendor' : 'New item'),
              tooltip:
                  _isVendorsTab ? 'Add a vendor' : 'Add an inventory item',
              onPressed: _onCreate,
            )
          : null,
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
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            // +1 leading row for the result-count header.
            itemCount: list.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return _CountHeader(count: list.length, lowOnly: showOnlyLow);
              }
              return _ItemCard(item: list[i - 1]);
            },
          ),
        );
      },
    );
  }
}

/// In-body header: a count [AppBadge] tinted to the active tab (danger when
/// listing low stock, neutral otherwise).
class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.count, required this.lowOnly});
  final int count;
  final bool lowOnly;

  @override
  Widget build(BuildContext context) {
    final noun = count == 1 ? 'item' : 'items';
    final label = lowOnly ? '$count low-stock $noun' : '$count $noun';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppBadge(
          text: label,
          tone: lowOnly ? AppBadgeTone.danger : AppBadgeTone.neutral,
          icon: lowOnly ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
        ),
      ),
    );
  }
}

/// A v1 list tile rendered as an [AppCard]: a tinted inventory icon (warning
/// tint for low stock), the item name, a one-line qty/unit subtitle, and a
/// trailing low-stock [AppBadge] when applicable.
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});
  final InventoryItem item;

  // Whole-number qty renders without a trailing ".0".
  String get _qtyLabel {
    final whole = item.onHand.truncateToDouble() == item.onHand;
    return item.onHand.toStringAsFixed(whole ? 0 : 2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final low = item.lowStock;
    // Low-stock items pick up the warning accent on their leading icon; the
    // trailing badge carries the explicit "Low stock" signal.
    final tint = low ? semantics.warning : scheme.primary;

    // Subtitle is always exactly one line (qty · unit, optional SKU prefix) so
    // row height stays constant whether or not an item has a SKU.
    final subtitle = [
      if (item.sku != null && item.sku!.isNotEmpty) item.sku!,
      '$_qtyLabel ${item.unit}',
    ].join(' · ');

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InventoryItemPage(itemId: item.id),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.inventory_2_outlined, color: tint, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: AppType.semibold),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (low)
            const AppBadge(text: 'Low stock', tone: AppBadgeTone.warning)
          else
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
