import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class FinancialReportsPage extends ConsumerWidget {
  const FinancialReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);
    return invoicesAsync.when(
      loading: () => const AppLoading(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(invoicesProvider),
      ),
      data: (invoices) {
        final now = DateTime.now();
        final thirtyDays = now.subtract(const Duration(days: 30));
        var revenue30d = 0.0;
        var outstanding = 0.0;
        var overdueCount = 0;
        final byStatus = <InvoiceStatus, int>{};
        for (final i in invoices) {
          byStatus[i.status] = (byStatus[i.status] ?? 0) + 1;
          if (i.issuedAt.isAfter(thirtyDays)) {
            revenue30d += i.amountPaid;
          }
          outstanding += i.balance;
          if (i.status == InvoiceStatus.overdue) overdueCount++;
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _BigStat(
              label: 'Collected (last 30 days)',
              value: '₹${revenue30d.toStringAsFixed(0)}',
              tone: AppBadgeTone.success,
            ),
            const SizedBox(height: AppSpacing.md),
            _BigStat(
              label: 'Outstanding',
              value: '₹${outstanding.toStringAsFixed(0)}',
              tone: outstanding > 0 ? AppBadgeTone.warning : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _BigStat(
              label: 'Overdue invoices',
              value: '$overdueCount',
              tone: overdueCount > 0 ? AppBadgeTone.danger : null,
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'By status'),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final s in InvoiceStatus.values)
                    AppListTile(
                      title: Text(s.label),
                      trailing: Text(
                        '${byStatus[s] ?? 0}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.label, required this.value, this.tone});
  final String label;
  final String value;
  final AppBadgeTone? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sem = AppSemanticColors.of(context);
    final (fg, bg) = switch (tone) {
      AppBadgeTone.success => (sem.success, sem.successContainer),
      AppBadgeTone.warning => (sem.warning, sem.warningContainer),
      AppBadgeTone.danger => (sem.danger, sem.dangerContainer),
      _ => (scheme.onSurface, null),
    };
    return AppCard(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: fg),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
