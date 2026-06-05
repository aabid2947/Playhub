import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_form_page.dart';
import 'package:playhub/features/inventory/presentation/movement_sheet.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
        body: AppLoading(),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _StockCard(item: item),
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'Recent movements'),
          const SizedBox(height: AppSpacing.sm),
          movesAsync.when(
            loading: () => const AppSkeletonList(count: 3),
            error: (e, _) => _InlineNote(
              icon: Icons.error_outline,
              tone: AppBadgeTone.danger,
              text: friendlyError(e),
            ),
            data: (moves) {
              if (moves.isEmpty) {
                return const _InlineNote(
                  icon: Icons.history,
                  text: 'No movements logged yet.',
                );
              }
              return Column(
                children: [
                  for (final m in moves)
                    AppListTile(
                      leading: Icon(_iconFor(m.kind)),
                      title: Row(
                        children: [
                          AppBadge(
                            text: m.kind.toUpperCase(),
                            tone: _toneFor(m.kind),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            m.qty.toStringAsFixed(
                              m.qty.truncateToDouble() == m.qty ? 0 : 2,
                            ),
                          ),
                        ],
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

  AppBadgeTone _toneFor(String kind) {
    switch (kind) {
      case 'in':
        return AppBadgeTone.success;
      case 'out':
        return AppBadgeTone.danger;
      case 'return':
        return AppBadgeTone.info;
      case 'adjustment':
        return AppBadgeTone.warning;
    }
    return AppBadgeTone.neutral;
  }
}

/// Compact inline note for sub-section empty / error states (avoids the
/// full-screen [AppEmptyState]/[AppErrorView] which expect bounded height).
class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.text,
    this.tone = AppBadgeTone.neutral,
  });

  final IconData icon;
  final String text;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    final color = switch (tone) {
      AppBadgeTone.danger => semantics.danger,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    final onHand = item.onHand.toStringAsFixed(
      item.onHand.truncateToDouble() == item.onHand ? 0 : 2,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.sku != null && item.sku!.isNotEmpty) ...[
            Text(
              'SKU: ${item.sku}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Row(
            children: [
              Text(
                '$onHand ${item.unit}',
                style: theme.textTheme.headlineSmall,
              ),
              if (item.lowStock) ...[
                const SizedBox(width: AppSpacing.sm),
                const AppBadge(text: 'Low stock', tone: AppBadgeTone.danger),
              ],
            ],
          ),
          if (item.reorderThreshold > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Reorder threshold: ${item.reorderThreshold}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: item.lowStock
                    ? semantics.danger
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (item.unitCost > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Unit cost: ₹${item.unitCost.toStringAsFixed(2)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(item.description!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
