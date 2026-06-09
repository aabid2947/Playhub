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

/// Inventory item detail — archetype C. An entity-colored gradient hero
/// (item-derived) with back/edit/delete circle buttons, a low-stock glass chip,
/// and a floating 3-up mini-stat row (on-hand · reorder · unit cost) overlapping
/// the band, then SKU / description info rows and the movement ledger.
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

  void _edit(InventoryItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryItemFormPage(existing: item),
      ),
    );
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
          padding: EdgeInsets.zero,
          children: [
            _Hero(
              item: item,
              canDelete: caps.manageInventory,
              onEdit: () => _edit(item),
              onDelete: () => _confirmDelete(item),
            ),
            // Body overlaps the hero band upward, v1-style.
            Transform.translate(
              offset: const Offset(0, -AppSpacing.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MiniStats(item: item),
                    const SizedBox(height: AppSpacing.lg),
                    _Details(item: item),
                    const SizedBox(height: AppSpacing.lg),
                    movesAsync.when(
                      loading: () => const Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppSectionHeader(
                            title: 'Movements',
                            icon: Icons.swap_vert_rounded,
                          ),
                          SizedBox(height: AppSpacing.sm),
                          AppSkeletonList(count: 3),
                        ],
                      ),
                      error: (e, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AppSectionHeader(
                            title: 'Movements',
                            icon: Icons.swap_vert_rounded,
                          ),
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
                          () => _visible = (_visible + _kMovementsPageSize)
                              .clamp(0, moves.length),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The item-colored gradient hero: back + edit/delete circle buttons, a tinted
/// box-icon mark, the item name + SKU sub, and a low-stock glass chip.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.item,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final InventoryItem item;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Entity hero: tint the gradient from the item name so each item reads as
    // its own card (pair = lighter→base of a deterministic accent color).
    final c = colorFromName(item.name);
    final sku = item.sku;
    return AppGradientHeader(
      colors: [c.withValues(alpha: 0.92), c],
      child: Column(
        children: [
          Row(
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              AppCircleIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit item',
                onTap: onEdit,
              ),
              if (canDelete) ...[
                const SizedBox(width: AppSpacing.sm),
                AppCircleIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete item',
                  onTap: onDelete,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            item.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          if (item.lowStock) ...[
            const SizedBox(height: AppSpacing.md),
            const AppGlassChip('Low stock', icon: Icons.warning_amber_rounded),
          ] else if (sku != null && sku.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppGlassChip('SKU $sku', icon: Icons.qr_code_2_rounded),
          ],
        ],
      ),
    );
  }
}

/// Floating 3-up mini-stat row that overlaps the hero band: on-hand quantity,
/// the reorder threshold, and the unit cost.
class _MiniStats extends StatelessWidget {
  const _MiniStats({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final semantics = AppSemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _MiniStat(
            icon: Icons.inventory_rounded,
            value: '${_qty(item.onHand)} ${item.unit}',
            label: 'On hand',
            tint: item.lowStock ? semantics.danger : scheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MiniStat(
            icon: Icons.low_priority_rounded,
            value: item.reorderThreshold > 0
                ? '${_qty(item.reorderThreshold)} ${item.unit}'
                : '—',
            label: 'Reorder at',
            tint: item.lowStock ? semantics.warning : scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MiniStat(
            icon: Icons.currency_rupee_rounded,
            value: item.unitCost > 0
                ? '₹${item.unitCost.toStringAsFixed(2)}'
                : '—',
            label: 'Unit cost',
            tint: scheme.secondary,
          ),
        ),
      ],
    );
  }

  static String _qty(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
}

/// A compact floating stat card used in the overlapping mini-stat row.
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Column(
        children: [
          Icon(icon, color: tint, size: 22),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: tint,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// SKU / reorder / description info rows in a "Details" section card, each with
/// a leading tinted icon so the card reads the same regardless of which optional
/// fields are populated.
class _Details extends StatelessWidget {
  const _Details({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desc = item.description;
    final rows = <Widget>[
      _InfoRow(
        icon: Icons.qr_code_2_outlined,
        label: 'SKU',
        value: (item.sku != null && item.sku!.isNotEmpty) ? item.sku! : '—',
      ),
      _InfoRow(
        icon: Icons.straighten_outlined,
        label: 'Unit',
        value: item.unit,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Details',
          icon: Icons.info_outline_rounded,
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i != rows.length - 1) const Divider(height: 1),
              ],
              if (desc != null && desc.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    desc,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// An info row: leading tinted icon, a small label and the value beneath it.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
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
          AppSectionHeader(
            title: 'Movements',
            icon: Icons.swap_vert_rounded,
          ),
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
          icon: Icons.swap_vert_rounded,
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
