import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/features/billing/presentation/fee_structure_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class FeeStructuresPage extends ConsumerWidget {
  const FeeStructuresPage({super.key});

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
              itemCount: fees.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _FeeTile(fee: fees[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const FeeStructureFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New fee'),
      ),
    );
  }
}

class _FeeTile extends ConsumerWidget {
  const _FeeTile({required this.fee});
  final FeeStructure fee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sportLabel = ref.watch(sportDisplayProvider((sportId: fee.sportId)));
    return AppListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(fee.name),
      subtitle: Text(
        [
          fee.type.label,
          if (sportLabel != '—') sportLabel,
          '₹${fee.baseAmount.toStringAsFixed(0)}${fee.taxPct > 0 ? ' + ${fee.taxPct.toStringAsFixed(0)}% tax' : ''}',
        ].join(' • '),
      ),
      trailing: fee.isActive ? null : const AppBadge(text: 'Inactive'),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => FeeStructureFormPage(existing: fee),
        ),
      ),
    );
  }
}
