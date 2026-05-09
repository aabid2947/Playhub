import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart' show PlanRow;

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
            onPressed: () {
              ref.invalidate(mySubscriptionProvider);
              ref.invalidate(mySaasInvoicesProvider);
              ref.invalidate(availablePlansProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          subAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (sub) {
              if (sub == null) return const Text('No subscription on file.');
              return _CurrentPlanCard(sub: sub);
            },
          ),
          const SizedBox(height: 12),
          Text('Plans', style: Theme.of(context).textTheme.titleMedium),
          plansAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
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
          const SizedBox(height: 12),
          Text('Past invoices',
              style: Theme.of(context).textTheme.titleMedium),
          invoicesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (rows) {
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No invoices yet.'),
                );
              }
              final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
              final df = DateFormat('dd MMM yyyy');
              return Card(
                child: Column(
                  children: [
                    for (final inv in rows) ...[
                      ListTile(
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
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall),
                            if (inv.balance > 0)
                              Text(
                                'Balance ${f.format(inv.balance)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current plan',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            plansAsync.when(
              loading: () => const Text('…'),
              error: (e, _) => Text('Error: $e'),
              data: (plans) {
                final p = plans.where((p) => p.id == sub.planId).firstOrNull;
                return Text(
                  p?.name ?? 'Unknown',
                  style: Theme.of(context).textTheme.headlineSmall,
                );
              },
            ),
            const SizedBox(height: 4),
            Text('Status: ${sub.status}'),
            Text('Cycle: ${sub.billingCycle}'),
            Text('Renews on ${df.format(sub.currentPeriodEnd)}'),
            if (sub.trialEndsAt != null)
              Text('Trial ends ${df.format(sub.trialEndsAt!)}'),
            if (sub.cancelledAt != null)
              Text('Cancelled ${df.format(sub.cancelledAt!)}'),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.isCurrent});
  final PlanRow plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (isCurrent) const Chip(label: Text('Current')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                '₹${plan.monthlyPrice.toStringAsFixed(0)}/month'
                '${plan.yearlyPrice == null ? '' : ' · ₹${plan.yearlyPrice!.toStringAsFixed(0)}/year'}'),
            if (plan.description != null && plan.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(plan.description!),
            ],
            if (plan.maxStudents != null || plan.maxCoaches != null) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (plan.maxStudents != null)
                    'Max ${plan.maxStudents} students',
                  if (plan.maxCoaches != null)
                    'Max ${plan.maxCoaches} coaches',
                  if (plan.maxCenters != null)
                    'Max ${plan.maxCenters} centers',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!isCurrent) ...[
              const SizedBox(height: 12),
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
      ),
    );
  }

  void _requestChange(BuildContext context, PlanRow plan) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'We\'ve noted your interest in ${plan.name}. '
          'Our team will reach out to confirm the change.',
        ),
      ),
    );
  }
}
