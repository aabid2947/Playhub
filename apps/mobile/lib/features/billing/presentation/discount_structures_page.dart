import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';
import 'package:playhub/features/billing/presentation/discount_structure_form_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Discount structures list — v1 "Sports-Light", archetype B (list).
///
/// Renders inside the Billing dashboard's TabBarView, so it stays
/// **app-bar-less**: a compact in-body header (title + count [AppBadge]) tops a
/// column of [AppCard] discount rows ([_DiscountTile]) showing the type and a
/// glanceable %/₹ value badge. The create FAB is gated on
/// [Capabilities.manageFinance] (RLS is the real gate — this just hides the
/// entry point for roles that can't create).
class DiscountStructuresPage extends ConsumerWidget {
  const DiscountStructuresPage({super.key});

  void _openForm(BuildContext context, {DiscountStructure? existing}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiscountStructureFormPage(existing: existing),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRows = ref.watch(discountStructuresProvider);
    final canManage = ref.watch(capabilitiesProvider).manageFinance;

    return Scaffold(
      body: asyncRows.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(discountStructuresProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const AppEmptyState(
              icon: Icons.local_offer_outlined,
              title: 'No discounts yet',
              subtitle: 'Define a sibling, scholarship, or promo discount, '
                  'then assign it to a student or a batch.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(discountStructuresProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                // Leave room so the last tile clears the FAB.
                AppSpacing.xxl + AppSpacing.xl,
              ),
              itemCount: rows.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (index == 0) return _ListHeader(count: rows.length);
                final item = rows[index - 1];
                return _DiscountTile(
                  item: item,
                  onTap: () => _openForm(context, existing: item),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add),
              label: const Text('New discount'),
            )
          : null,
    );
  }
}

/// Compact in-body header: title + a neutral count [AppBadge]. No hero band —
/// this page lives under the Billing tab chrome.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            'Discounts',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: AppType.bold,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppBadge(text: '$count'),
        ],
      ),
    );
  }
}

/// A single discount row: a tinted offer-tag icon tile → name → one tight
/// type · description line, with the %/₹ value badge and active/inactive status
/// stacked on the trailing edge. The value badge is the at-a-glance fact.
class _DiscountTile extends StatelessWidget {
  const _DiscountTile({required this.item, required this.onTap});

  final DiscountStructure item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = colorFromName(item.name);

    // Pair the discount type with its description (when set) on one tight line.
    final subtitle = <String>[
      item.type.label,
      if (item.description != null && item.description!.isNotEmpty)
        item.description!,
    ].join('  •  ');

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: AppListTile(
        wrapLeading: false,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(Icons.local_offer_outlined, color: tint, size: 20),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // The value badge is the glanceable fact: % vs ₹, brand-toned.
            Text(
              item.summary,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: AppType.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppBadge(
              text: item.isActive ? 'Active' : 'Inactive',
              tone: item.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
            ),
          ],
        ),
      ),
    );
  }
}
