import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/features/billing/presentation/fee_structure_form_page.dart';
import 'package:playhub/features/payment_gateways/data/payment_gateway_providers.dart';
import 'package:playhub/features/payment_gateways/presentation/payment_gateways_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Fee structures list — v1 "Sports-Light", archetype B (list).
///
/// Renders inside the Billing dashboard's TabBarView, so it stays
/// **app-bar-less**: a compact in-body header (title + count [AppBadge]) tops a
/// column of [AppCard] fee rows ([_FeeTile]) showing amount + cadence. The
/// create FAB is gated on [Capabilities.manageFinance] (RLS is the real gate —
/// this just hides the entry point for roles that can't create).
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
    final canManage = ref.watch(capabilitiesProvider).manageFinance;

    return Scaffold(
      body: Column(
        children: [
          // Online fee collection needs the academy's own gateway connected —
          // surface a setup prompt for the owner until it is (the backend hard-
          // requires it, so without this the parent's "Pay" just errors).
          const _GatewaySetupBanner(),
          Expanded(
            child: feesAsync.when(
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                // Leave room so the last tile clears the FAB.
                AppSpacing.xxl + AppSpacing.xl,
              ),
              itemCount: fees.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (index == 0) return _ListHeader(count: fees.length);
                return _FeeTile(
                  fee: fees[index - 1],
                  onTap: () => _openForm(context, existing: fees[index - 1]),
                );
              },
            ),
          );
        },
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add),
              label: const Text('New fee'),
            )
          : null,
    );
  }
}

/// Owner-only prompt: the academy must connect its own Razorpay account before
/// students can pay fees online (the backend requires it). Hidden once a gateway
/// is enabled + configured, or for roles that can't manage gateways.
class _GatewaySetupBanner extends ConsumerWidget {
  const _GatewaySetupBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(capabilitiesProvider).managePaymentGateways) {
      return const SizedBox.shrink();
    }
    final gateways = ref.watch(paymentGatewaysProvider).valueOrNull;
    if (gateways == null) return const SizedBox.shrink();
    final ready =
        gateways.values.any((g) => g.isEnabled && g.isConfigured);
    if (ready) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Set up online payments',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: AppType.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Students can't pay fees online until you connect your academy's "
              'Razorpay account. Add your keys and the webhook to start '
              'collecting payments.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const PaymentGatewaysPage(),
                  ),
                ),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Set up payments'),
              ),
            ),
          ],
        ),
      ),
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
            'Fee structures',
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

/// A single fee structure row: a tinted receipt icon tile → name → one tight
/// cadence · sport line, with the total ₹ amount and active/inactive status
/// stacked on the trailing edge.
class _FeeTile extends ConsumerWidget {
  const _FeeTile({required this.fee, required this.onTap});

  final FeeStructure fee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sportLabel = ref.watch(sportDisplayProvider((sportId: fee.sportId)));
    final tint = colorFromName(fee.name);
    // A batch-tagged fee is a price for one batch — name it, so several
    // same-named fees at different prices are tellable apart at a glance.
    final batchName = fee.batchId == null
        ? null
        : (ref.watch(batchesProvider).valueOrNull ?? const <Batch>[])
            .where((b) => b.id == fee.batchId)
            .firstOrNull
            ?.name;

    final subtitle = <String>[
      fee.type.label,
      if (fee.pricePerDay != null)
        '₹${fee.pricePerDay!.toStringAsFixed(0)}/day'
        '${fee.daysPerWeek != null ? ' × ${fee.daysPerWeek}d/wk' : ''}',
      if (batchName != null) batchName else if (sportLabel != '—') sportLabel,
      if (fee.taxPct > 0) '+${fee.taxPct.toStringAsFixed(0)}% tax',
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
          child: Icon(Icons.receipt_long_outlined, color: tint, size: 20),
        ),
        title: Text(
          fee.name,
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
            Text(
              '₹${fee.totalAmount.toStringAsFixed(0)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: AppType.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppBadge(
              text: fee.isActive ? 'Active' : 'Inactive',
              tone: fee.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
            ),
          ],
        ),
      ),
    );
  }
}
