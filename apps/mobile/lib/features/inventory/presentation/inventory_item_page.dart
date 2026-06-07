import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_item_form_page.dart';
import 'package:playhub/features/inventory/presentation/movement_sheet.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// How many movements to show before the "Show more" cue kicks in. The
/// provider already caps the fetch at 100, so this is a purely client-side
/// reveal over the already-loaded list (no extra query).
const _kMovementsPageSize = 20;

class InventoryItemPage extends ConsumerStatefulWidget {
  const InventoryItemPage({required this.itemId, super.key});
  final String itemId;

  @override
  ConsumerState<InventoryItemPage> createState() => _InventoryItemPageState();
}

class _InventoryItemPageState extends ConsumerState<InventoryItemPage> {
  int _visible = _kMovementsPageSize;

  /// Hard-delete the item after confirmation. RLS limits this to admin tier +
  /// center_admin (own center); `manageInventory` mirrors that on the UI.
  Future<void> _confirmDelete(InventoryItem item) async {
    final ok = await confirmAction(
      context,
      title: 'Delete "${item.name}"?',
      message:
          'This permanently removes the item and its movement history. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final repo = await ref.read(inventoryRepoProvider.future);
      if (repo == null) return;
      await repo.deleteItem(item.id);
      ref.invalidate(inventoryItemsProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Item deleted.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inventoryItemsProvider).valueOrNull ?? const [];
    final item = items.where((i) => i.id == widget.itemId).firstOrNull;
    final movesAsync = ref.watch(itemMovementsProvider(widget.itemId));
    final caps = ref.watch(capabilitiesProvider);

    if (item == null) {
      return const Scaffold(
        body: AppLoading(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit item',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InventoryItemFormPage(existing: item),
              ),
            ),
          ),
          if (caps.manageInventory)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete item',
              onPressed: () => _confirmDelete(item),
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(inventoryItemsProvider)
            ..invalidate(itemMovementsProvider(widget.itemId));
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _StockCard(item: item),
            const SizedBox(height: AppSpacing.xl),
            movesAsync.when(
              loading: () => const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSectionHeader(title: 'Movements'),
                  SizedBox(height: AppSpacing.sm),
                  AppSkeletonList(count: 3),
                ],
              ),
              error: (e, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeader(title: 'Movements'),
                  const SizedBox(height: AppSpacing.sm),
                  _InlineNote(
                    icon: Icons.error_outline,
                    tone: AppBadgeTone.danger,
                    text: friendlyError(e),
                  ),
                ],
              ),
              data: (moves) => _MovementsSection(
                moves: moves,
                visible: _visible,
                onShowMore: () => setState(
                  () => _visible =
                      (_visible + _kMovementsPageSize).clamp(0, moves.length),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Movements list with a consistent tile rhythm and an explicit cap +
/// "show more" cue over the already-fetched list.
class _MovementsSection extends StatelessWidget {
  const _MovementsSection({
    required this.moves,
    required this.visible,
    required this.onShowMore,
  });

  final List<InventoryMovement> moves;
  final int visible;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (moves.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(title: 'Movements'),
          SizedBox(height: AppSpacing.sm),
          _InlineNote(
            icon: Icons.history,
            text: 'No movements logged yet.',
          ),
        ],
      );
    }

    final shown = moves.take(visible).toList(growable: false);
    final remaining = moves.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Movements',
          trailing: AppBadge(text: '${moves.length}'),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final m in shown) _MovementTile(movement: m),
        if (remaining > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton.icon(
              onPressed: onShowMore,
              icon: const Icon(Icons.expand_more),
              label: Text('Show more · $remaining'),
            ),
          ),
        ] else if (moves.length > _kMovementsPageSize) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              'Showing all ${moves.length} movements',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A single movement row: tinted kind icon → kind badge + signed qty →
/// one tight metadata line (date · ref · notes).
class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});
  final InventoryMovement movement;

  static final _df = DateFormat('dd MMM yyyy · HH:mm');

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final qty = m.qty.toStringAsFixed(
      m.qty.truncateToDouble() == m.qty ? 0 : 2,
    );
    final meta = [
      _df.format(m.performedAt),
      if (m.reference != null && m.reference!.isNotEmpty) 'ref: ${m.reference}',
      if (m.notes != null && m.notes!.isNotEmpty) m.notes!,
    ].join(' · ');

    return AppListTile(
      leading: Icon(_iconFor(m.kind)),
      title: Row(
        children: [
          AppBadge(text: m.kind.toUpperCase(), tone: _toneFor(m.kind)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(qty, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      subtitle: Text(meta),
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

/// Stable stock-summary header card: an on-hand metric callout up top, then a
/// fixed-rhythm run of fact rows so the card reads the same regardless of
/// which optional fields are populated.
class _StockCard extends StatelessWidget {
  const _StockCard({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final onHand = item.onHand.toStringAsFixed(
      item.onHand.truncateToDouble() == item.onHand ? 0 : 2,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // On-hand metric callout.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'On hand',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '$onHand ${item.unit}',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
              if (item.lowStock)
                const AppBadge(text: 'Low stock', tone: AppBadgeTone.danger),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          // Fixed-rhythm fact rows.
          _FactRow(
            label: 'SKU',
            value: (item.sku != null && item.sku!.isNotEmpty)
                ? item.sku!
                : '—',
          ),
          const SizedBox(height: AppSpacing.sm),
          _FactRow(
            label: 'Reorder threshold',
            value: item.reorderThreshold > 0
                ? '${_qty(item.reorderThreshold)} ${item.unit}'
                : 'Not set',
            valueColor: item.lowStock ? semantics.danger : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FactRow(
            label: 'Unit cost',
            value: item.unitCost > 0
                ? '₹${item.unitCost.toStringAsFixed(2)}'
                : '—',
          ),
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Text(
              item.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _qty(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
}

/// One label/value row inside the stock-summary card, laid out so every fact
/// aligns consistently.
class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
