import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Tab body under the billing dashboard — the parent page owns the AppBar +
/// TabBar, so this screen is intentionally app-bar-less.
///
/// All figures derive from [allInvoicesProvider] — the academy-wide, *unfiltered*
/// invoice list — so the report's totals are never re-scoped by the invoice-list
/// filter (which the by-status tap-through pivots). The window is fixed at the
/// last 30 days (a configurable date range would need a new query).
class FinancialReportsPage extends ConsumerWidget {
  const FinancialReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(allInvoicesProvider);
    return invoicesAsync.when(
      loading: () => const AppSkeletonList(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(allInvoicesProvider),
      ),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const AppEmptyState(
            icon: Icons.insights_outlined,
            title: 'Nothing to report yet',
            subtitle:
                'Financial figures appear here once invoices are issued.',
          );
        }

        final report = _Report.from(invoices);

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(allInvoicesProvider),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const AppSectionHeader(title: 'Last 30 days'),
              const SizedBox(height: AppSpacing.sm),
              _StatGrid(
                tiles: [
                  _StatData(
                    icon: Icons.payments_outlined,
                    label: 'Collected (30d)',
                    value: _inr(report.revenue30d),
                    tone: AppBadgeTone.success,
                  ),
                  _StatData(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Outstanding',
                    value: _inr(report.outstanding),
                    tone: report.outstanding > 0
                        ? AppBadgeTone.warning
                        : null,
                  ),
                  _StatData(
                    icon: Icons.warning_amber_outlined,
                    label: 'Overdue invoices',
                    value: '${report.overdueCount}',
                    tone:
                        report.overdueCount > 0 ? AppBadgeTone.danger : null,
                  ),
                  _StatData(
                    icon: Icons.receipt_long_outlined,
                    label: 'Total invoices',
                    value: '${invoices.length}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const AppSectionHeader(title: 'By status'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final s in InvoiceStatus.values)
                      _StatusRow(
                        status: s,
                        count: report.byStatus[s] ?? 0,
                        // Tapping pivots the shared invoice filter to this
                        // status and jumps to the Money tab, where the invoice
                        // list watches `invoiceFilterProvider`.
                        onTap: () => _openFiltered(context, ref, s),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openFiltered(BuildContext context, WidgetRef ref, InvoiceStatus s) {
    ref.read(invoiceFilterProvider.notifier).state =
        InvoiceFilter(status: s);
    DefaultTabController.of(context).animateTo(0);
  }
}

String _inr(double v) => '₹${v.toStringAsFixed(0)}';

/// KPI figures derived once from the invoice list.
class _Report {
  const _Report({
    required this.revenue30d,
    required this.outstanding,
    required this.overdueCount,
    required this.byStatus,
  });

  factory _Report.from(List<Invoice> invoices) {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    var revenue30d = 0.0;
    var outstanding = 0.0;
    var overdueCount = 0;
    final byStatus = <InvoiceStatus, int>{};
    for (final i in invoices) {
      byStatus[i.status] = (byStatus[i.status] ?? 0) + 1;
      if (i.issuedAt.isAfter(thirtyDaysAgo)) {
        revenue30d += i.amountPaid;
      }
      outstanding += i.balance;
      if (i.status == InvoiceStatus.overdue) overdueCount++;
    }
    return _Report(
      revenue30d: revenue30d,
      outstanding: outstanding,
      overdueCount: overdueCount,
      byStatus: byStatus,
    );
  }

  final double revenue30d;
  final double outstanding;
  final int overdueCount;
  final Map<InvoiceStatus, int> byStatus;
}

/// Immutable data backing one [AppStatTile] in the KPI grid.
class _StatData {
  const _StatData({
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final AppBadgeTone? tone;
}

/// Responsive 2-up grid of KPI tiles (§3.4). Wraps so tiles stack on narrow
/// widths rather than crushing.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_StatData> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoUp = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final t in tiles)
              SizedBox(
                width: twoUp,
                child: AppStatTile(
                  icon: t.icon,
                  label: t.label,
                  value: t.value,
                  color: _accent(context, t.tone),
                ),
              ),
          ],
        );
      },
    );
  }

  Color? _accent(BuildContext context, AppBadgeTone? tone) {
    final sem = AppSemanticColors.of(context);
    return switch (tone) {
      AppBadgeTone.success => sem.success,
      AppBadgeTone.warning => sem.warning,
      AppBadgeTone.danger => sem.danger,
      AppBadgeTone.info => sem.info,
      _ => null,
    };
  }
}

/// A single "by status" row: the status label and a tone-coloured count badge;
/// tapping (when count > 0) pivots the invoice list to this status.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.count,
    required this.onTap,
  });

  final InvoiceStatus status;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The tone-coloured badge carries the count so status is encoded by both
    // colour and number, not colour alone (§3.6); the title names the status.
    return AppListTile(
      title: Text(status.label),
      trailing: AppBadge(text: '$count', tone: _tone(status)),
      onTap: count > 0 ? onTap : null,
    );
  }

  AppBadgeTone _tone(InvoiceStatus s) => switch (s) {
        InvoiceStatus.paid => AppBadgeTone.success,
        InvoiceStatus.partial => AppBadgeTone.warning,
        InvoiceStatus.overdue => AppBadgeTone.danger,
        InvoiceStatus.issued => AppBadgeTone.info,
        InvoiceStatus.cancelled => AppBadgeTone.neutral,
        InvoiceStatus.draft => AppBadgeTone.neutral,
      };
}
