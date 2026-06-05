import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart'
    show PlanRow;
import 'package:playhub/shared/widgets/widgets.dart';

/// Academy-owner facing subscription management.
/// - Shows current plan + status + period_end
/// - Lists available plans with upgrade/downgrade requests
/// - Lists past saas_invoices (paid + outstanding)
///
/// Plan changes route through a "request" SnackBar today (super_admin
/// applies the change manually). True self-serve plan changes wired to
/// Razorpay subscriptions land in v1.x.
class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(mySubscriptionProvider);
    final invoicesAsync = ref.watch(mySaasInvoicesProvider);
    final plansAsync = ref.watch(availablePlansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref
              ..invalidate(mySubscriptionProvider)
              ..invalidate(mySaasInvoicesProvider)
              ..invalidate(availablePlansProvider),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          subAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => _ErrorText(message: friendlyError(e)),
            data: (sub) {
              if (sub == null) {
                return const _MutedText('No subscription on file.');
              }
              return _CurrentPlanCard(sub: sub);
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'Plans'),
          const SizedBox(height: AppSpacing.sm),
          plansAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => _ErrorText(message: friendlyError(e)),
            data: (plans) {
              final currentPlanId = subAsync.valueOrNull?.planId;
              return Column(
                children: [
                  for (final p in plans)
                    _PlanCard(plan: p, isCurrent: p.id == currentPlanId),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'Past invoices'),
          const SizedBox(height: AppSpacing.sm),
          invoicesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => _ErrorText(message: friendlyError(e)),
            data: (rows) {
              if (rows.isEmpty) {
                return const _MutedText('No invoices yet.');
              }
              final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
              final df = DateFormat('dd MMM yyyy');
              return AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final inv in rows) ...[
                      AppListTile(
                        title: Text(inv.invoiceNumber),
                        subtitle: Text(
                          'Issued ${df.format(inv.issuedAt)} · '
                          'due ${df.format(inv.dueDate)} · ${inv.status}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(f.format(inv.totalAmount),
                                style: Theme.of(context).textTheme.titleSmall),
                            if (inv.balance > 0)
                              Text(
                                'Balance ${f.format(inv.balance)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppSemanticColors.of(context)
                                          .danger,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CurrentPlanCard extends ConsumerWidget {
  const _CurrentPlanCard({required this.sub});
  final AcademySubscription sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(availablePlansProvider);
    final df = DateFormat('dd MMM yyyy');
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current plan',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          plansAsync.when(
            loading: () => const Text('…'),
            error: (e, _) => _ErrorText(message: friendlyError(e)),
            data: (plans) {
              final p = plans.where((p) => p.id == sub.planId).firstOrNull;
              return Text(
                p?.name ?? 'Unknown',
                style: Theme.of(context).textTheme.headlineSmall,
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Status: ${sub.status}', style: muted),
          Text('Cycle: ${sub.billingCycle}', style: muted),
          Text('Renews on ${df.format(sub.currentPeriodEnd)}', style: muted),
          if (sub.trialEndsAt != null)
            Text('Trial ends ${df.format(sub.trialEndsAt!)}', style: muted),
          if (sub.cancelledAt != null)
            Text('Cancelled ${df.format(sub.cancelledAt!)}', style: muted),
        ],
      ),
    );
  }
}

/// Muted secondary line for empty/placeholder messages.
class _MutedText extends StatelessWidget {
  const _MutedText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// Inline danger-toned error line for sub-section `when` errors.
class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(color: AppSemanticColors.of(context).danger),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.isCurrent});
  final PlanRow plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (isCurrent)
                const AppBadge(text: 'Current', tone: AppBadgeTone.brand),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '₹${plan.monthlyPrice.toStringAsFixed(0)}/month'
            '${plan.yearlyPrice == null ? '' : ' · ₹${plan.yearlyPrice!.toStringAsFixed(0)}/year'}',
          ),
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(plan.description!, style: muted),
          ],
          if (plan.maxStudents != null || plan.maxCoaches != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                if (plan.maxStudents != null)
                  'Max ${plan.maxStudents} students',
                if (plan.maxCoaches != null) 'Max ${plan.maxCoaches} coaches',
                if (plan.maxCenters != null) 'Max ${plan.maxCenters} centers',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (!isCurrent) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => _requestChange(context, plan),
                child: const Text('Request change'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _requestChange(BuildContext context, PlanRow plan) {
    AppSnackbar.info(
      context,
      "We've noted your interest in ${plan.name}. "
      'Our team will reach out to confirm the change.',
    );
  }
}
