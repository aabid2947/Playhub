import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';
import 'package:playhub/features/billing/presentation/discount_structure_form_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
              itemCount: rows.length + 1,
              separatorBuilder: (_, index) => index == 0
                  ? const SizedBox.shrink()
                  : const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      0,
                    ),
                    child: AppSectionHeader(
                      title: rows.length == 1
                          ? '1 discount'
                          : '${rows.length} discounts',
                    ),
                  );
                }
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('New discount'),
      ),
    );
  }
}

class _DiscountTile extends StatelessWidget {
  const _DiscountTile({required this.item, required this.onTap});

  final DiscountStructure item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Subtitle pairs the discount type with its description (when set); the
    // value itself moves to a glanceable trailing badge.
    final subtitleParts = <String>[
      item.type.label,
      if (item.description != null && item.description!.isNotEmpty)
        item.description!,
    ];
    return AppListTile(
      leading: const Icon(Icons.local_offer_outlined),
      title: Row(
        children: [
          Flexible(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!item.isActive) ...[
            const SizedBox(width: AppSpacing.sm),
            const AppBadge(text: 'Inactive'),
          ],
        ],
      ),
      subtitle: Text(
        subtitleParts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // The value badge is the at-a-glance fact: % vs ₹, brand-toned.
      trailing: AppBadge(
        text: item.summary,
        tone: item.isActive ? AppBadgeTone.brand : AppBadgeTone.neutral,
      ),
      onTap: onTap,
    );
  }
}
