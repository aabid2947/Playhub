import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// System health + global revenue snapshot.
///
/// App-bar-less body of the super-admin shell (the shell owns the single,
/// constant AppBar) — do not add a Scaffold/AppBar here.
class GlobalHealthPage extends ConsumerWidget {
  const GlobalHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(globalKpiProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(allAcademiesProvider)
          ..invalidate(globalKpiProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          kpiAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: AppLoading(),
            ),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(globalKpiProvider),
            ),
            data: (k) => _HealthBody(k),
          ),
        ],
      ),
    );
  }
}

class _HealthBody extends StatelessWidget {
  const _HealthBody(this.k);

  final GlobalKpi k;

  @override
  Widget build(BuildContext context) {
    final sem = AppSemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlobalRevenueCard(
          totalRevenue: k.totalRevenue,
          outstandingAmount: k.outstandingAmount,
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSectionHeader(title: 'Academies'),
        // "Active" (is_active) is a different axis from the four subscription
        // states below, so it leads as a full-width emphasis tile. That also
        // tidies the odd count: a clean 2×2 grid of the 4 states follows, with
        // no orphaned fifth tile.
        AppStatTile(
          icon: Icons.check_circle_outline,
          label: 'Active academies',
          value: '${k.academiesActive}',
          color: sem.success,
        ),
        const SizedBox(height: AppSpacing.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.4,
          children: [
            AppStatTile(
              icon: Icons.schedule_outlined,
              label: 'Trial',
              value: '${k.academiesTrial}',
              color: sem.info,
            ),
            AppStatTile(
              icon: Icons.payments_outlined,
              label: 'Paying',
              value: '${k.academiesPaying}',
            ),
            AppStatTile(
              icon: Icons.warning_amber_outlined,
              label: 'Past due',
              value: '${k.academiesPastDue}',
              color: sem.warning,
            ),
            AppStatTile(
              icon: Icons.block_outlined,
              label: 'Suspended',
              value: '${k.academiesSuspended}',
              color: sem.danger,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSectionHeader(title: 'System'),
        const _SystemHealthCard(),
      ],
    );
  }
}

/// Headline global-revenue callout: the total as the hero value, with
/// outstanding dues as a clearly-delimited secondary fact.
class _GlobalRevenueCard extends StatelessWidget {
  const _GlobalRevenueCard({
    required this.totalRevenue,
    required this.outstandingAmount,
  });

  final double totalRevenue;
  final double outstandingAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Global revenue',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            f.format(totalRevenue),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: AppType.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: sem.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Outstanding',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                f.format(outstandingAmount),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppType.semibold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Placeholder for the full status board, clearly marked as deferred to v1.1.
class _SystemHealthCard extends StatelessWidget {
  const _SystemHealthCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.cloud_done_outlined, color: sem.success),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'System health',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const AppBadge(text: 'v1.1', tone: AppBadgeTone.info),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Edge Functions + cron deployed. The full status board '
                  'lands in v1.1.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
