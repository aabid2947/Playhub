import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// System health + global revenue snapshot.
class GlobalHealthPage extends ConsumerWidget {
  const GlobalHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(globalKpiProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(allAcademiesProvider);
        ref.invalidate(globalKpiProvider);
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
            data: (k) {
              final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Global revenue',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          f.format(k.totalRevenue),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text('Outstanding: ${f.format(k.outstandingAmount)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const AppSectionHeader(title: 'Academies'),
                  const SizedBox(height: AppSpacing.sm),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1.4,
                    children: [
                      AppStatTile(
                        icon: Icons.check_circle_outline,
                        label: 'Active',
                        value: '${k.academiesActive}',
                        color: AppPalette.success,
                      ),
                      AppStatTile(
                        icon: Icons.schedule_outlined,
                        label: 'Trial',
                        value: '${k.academiesTrial}',
                        color: AppPalette.info,
                      ),
                      AppStatTile(
                        icon: Icons.payments_outlined,
                        label: 'Paying (active)',
                        value: '${k.academiesPaying}',
                      ),
                      AppStatTile(
                        icon: Icons.warning_amber_outlined,
                        label: 'Past due',
                        value: '${k.academiesPastDue}',
                        color: AppPalette.warning,
                      ),
                      AppStatTile(
                        icon: Icons.block_outlined,
                        label: 'Suspended',
                        value: '${k.academiesSuspended}',
                        color: AppPalette.danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: const Text('System health'),
                      subtitle: const Text(
                        'Edge Functions + cron deployed; full status board '
                        'lands in v1.1',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
