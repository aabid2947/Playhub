import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Reports tab body under the billing dashboard — v1 "Sports-Light",
/// archetype E (finance). The parent page owns the AppBar + TabBar, so this
/// screen is intentionally app-bar-less: it leads with an in-body NAVY gradient
/// stat banner (collected / outstanding / overdue) and lets the body overlap it
/// upward, rather than fighting the tab chrome with its own app bar.
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
            padding: EdgeInsets.zero,
            children: [
              _ReportHero(report: report, invoiceCount: invoices.length),
              // Body overlaps the navy band upward, v1-style.
              Transform.translate(
                offset: const Offset(0, -AppSpacing.xl),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppSectionHeader(
                        title: 'By status',
                        icon: Icons.receipt_long_outlined,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final s in InvoiceStatus.values)
                              _StatusRow(
                                status: s,
                                count: report.byStatus[s] ?? 0,
                                // Tapping pivots the shared invoice filter to
                                // this status and jumps to the Money tab, where
                                // the invoice list watches
                                // `invoiceFilterProvider`.
                                onTap: () => _openFiltered(context, ref, s),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
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

/// Compact INR for the big hero figures (e.g. `₹3.1L`).
final _compactInr =
    NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');

/// Archetype-E finance hero: an in-body NAVY gradient band leading with the
/// three headline money figures (collected · outstanding · overdue) as big
/// [_BigStat]s, plus a translucent [AppHeroStatRow] summary strip. No back
/// button — this renders inside the Reports tab, not as a pushed page.
class _ReportHero extends StatelessWidget {
  const _ReportHero({required this.report, required this.invoiceCount});

  final _Report report;
  final int invoiceCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppGradientHeader(
      colors: AppPalette.navyGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 30 days',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                Icons.payments_outlined,
                size: 15,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Collected this month · pull down to reload',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _BigStat(
            label: 'Collected (30d)',
            value: _compactInr.format(report.revenue30d),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppHeroStatRow(
            stats: [
              (_compactInr.format(report.outstanding), 'Outstanding'),
              ('${report.overdueCount}', 'Overdue'),
              ('$invoiceCount', 'Invoices'),
            ],
          ),
        ],
      ),
    );
  }
}

/// The single dominant rupee figure in the navy hero — white-on-gradient, so it
/// reads as the headline number the rest of the strip supports.
class _BigStat extends StatelessWidget {
  const _BigStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontWeight: AppType.heavy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: AppType.semibold,
          ),
        ),
      ],
    );
  }
}

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
