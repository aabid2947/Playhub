import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/features/billing/presentation/fee_structure_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class FeeStructuresPage extends ConsumerWidget {
  const FeeStructuresPage({super.key});

  void _openForm(BuildContext context, {FeeStructure? existing}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FeeStructureFormPage(existing: existing),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feesAsync = ref.watch(feeStructuresProvider);
    return Scaffold(
      body: feesAsync.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(feeStructuresProvider),
        ),
        data: (fees) {
          if (fees.isEmpty) {
            return const AppEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No fee structures yet',
              subtitle: 'Create one to start billing students.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(feeStructuresProvider),
            child: ListView.separated(
              itemCount: fees.length + 1,
              separatorBuilder: (_, index) =>
                  index == 0 ? const SizedBox.shrink() : const Divider(height: 1),
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
                      title: fees.length == 1
                          ? '1 fee structure'
                          : '${fees.length} fee structures',
                    ),
                  );
                }
                return _FeeTile(
                  fee: fees[index - 1],
                  onTap: () => _openForm(context, existing: fees[index - 1]),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('New fee'),
      ),
    );
  }
}

class _FeeTile extends ConsumerWidget {
  const _FeeTile({required this.fee, required this.onTap});

  final FeeStructure fee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sportLabel = ref.watch(sportDisplayProvider((sportId: fee.sportId)));
    final terms = <String>[
      fee.type.label,
      if (sportLabel != '—') sportLabel,
      '₹${fee.baseAmount.toStringAsFixed(0)}'
          '${fee.taxPct > 0 ? ' + ${fee.taxPct.toStringAsFixed(0)}% tax' : ''}',
    ];
    return AppListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(fee.name),
      subtitle: Text(
        terms.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AppBadge(
        text: fee.isActive ? 'Active' : 'Inactive',
        tone: fee.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
      ),
      onTap: onTap,
    );
  }
}
