import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart'
    show PlanRow;
import 'package:playhub/shared/widgets/widgets.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _inrFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

/// Academy-owner facing subscription management.
/// - Shows current plan + status + period_end with a renewal/trial badge
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
      body: RefreshIndicator(
        onRefresh: () async => ref
          ..invalidate(mySubscriptionProvider)
          ..invalidate(mySaasInvoicesProvider)
          ..invalidate(availablePlansProvider),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // ── Current plan ─────────────────────────────────────────────
            subAsync.when(
              loading: () => const AppCard(child: AppLoading()),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(mySubscriptionProvider),
              ),
              data: (sub) {
                if (sub == null) {
                  return const AppEmptyState(
                    icon: Icons.workspace_premium_outlined,
                    title: 'No subscription on file',
                    subtitle:
                        'Your academy is not on a billing plan yet. Our team '
                        'will reach out to set one up.',
                  );
                }
                return _CurrentPlanCard(sub: sub);
              },
            ),

            // ── Plans ────────────────────────────────────────────────────
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Plans'),
            const SizedBox(height: AppSpacing.sm),
            plansAsync.when(
              loading: () => const AppLoading(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(availablePlansProvider),
              ),
              data: (plans) {
                if (plans.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.sell_outlined,
                    title: 'No plans available',
                    subtitle: 'There are no active plans to compare right now.',
                  );
                }
                final currentPlanId = subAsync.valueOrNull?.planId;
                return Column(
                  children: [
                    for (final p in plans)
                      _PlanCard(plan: p, isCurrent: p.id == currentPlanId),
                  ],
                );
              },
            ),

            // ── Past invoices ────────────────────────────────────────────
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Past invoices'),
            const SizedBox(height: AppSpacing.sm),
            invoicesAsync.when(
              loading: () => const AppLoading(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(mySaasInvoicesProvider),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No invoices yet',
                    subtitle: 'Your subscription invoices will appear here.',
                  );
                }
                return AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _SaasInvoiceTile(invoice: rows[i]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Header card for the academy's current subscription — plan name, a
/// status/renewal [AppBadge], and the key billing facts.
class _CurrentPlanCard extends ConsumerWidget {
  const _CurrentPlanCard({required this.sub});
  final AcademySubscription sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plansAsync = ref.watch(availablePlansProvider);
    final plan =
        plansAsync.valueOrNull?.where((p) => p.id == sub.planId).firstOrNull;
    final (badgeLabel, badgeTone) = _statusBadge(sub);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current plan',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: AppType.trackingWider,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  plan?.name ?? 'Unknown plan',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppBadge(text: badgeLabel, tone: badgeTone),
            ],
          ),
          if (plan?.description != null && plan!.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              plan.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          _FactRow(
            icon: Icons.event_repeat_outlined,
            label: 'Billing cycle',
            value: _cycleLabel(sub.billingCycle),
          ),
          _FactRow(
            icon: Icons.autorenew_outlined,
            label: sub.cancelledAt != null ? 'Active until' : 'Renews on',
            value: _dateFmt.format(sub.currentPeriodEnd),
          ),
          if (sub.trialEndsAt != null)
            _FactRow(
              icon: Icons.hourglass_bottom_outlined,
              label: 'Trial ends',
              value: _dateFmt.format(sub.trialEndsAt!),
            ),
          if (sub.cancelledAt != null)
            _FactRow(
              icon: Icons.cancel_outlined,
              label: 'Cancelled',
              value: _dateFmt.format(sub.cancelledAt!),
            ),
        ],
      ),
    );
  }

  /// Maps subscription state → a labelled status badge. Trial and
  /// cancellation take precedence over the raw status string.
  (String, AppBadgeTone) _statusBadge(AcademySubscription s) {
    if (s.cancelledAt != null) {
      return ('Cancelled', AppBadgeTone.danger);
    }
    if (s.trialEndsAt != null && s.trialEndsAt!.isAfter(DateTime.now())) {
      return ('Trial', AppBadgeTone.info);
    }
    return switch (s.status.toLowerCase()) {
      'active' => ('Active', AppBadgeTone.success),
      'trialing' || 'trial' => ('Trial', AppBadgeTone.info),
      'past_due' || 'unpaid' => ('Past due', AppBadgeTone.danger),
      'cancelled' || 'canceled' => ('Cancelled', AppBadgeTone.danger),
      'paused' => ('Paused', AppBadgeTone.warning),
      _ => (_titleCase(s.status), AppBadgeTone.neutral),
    };
  }
}

String _cycleLabel(String cycle) => switch (cycle.toLowerCase()) {
      'monthly' || 'month' => 'Monthly',
      'yearly' || 'annual' || 'year' => 'Yearly',
      _ => _titleCase(cycle),
    };

String _titleCase(String raw) {
  if (raw.isEmpty) return raw;
  final cleaned = raw.replaceAll('_', ' ');
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

/// A single icon + label + value row used inside the current-plan card.
class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A comparable plan card: aligned price block + a fixed set of limit rows so
/// cards line up vertically and read as a comparison.
class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.isCurrent});
  final PlanRow plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name, style: theme.textTheme.titleMedium),
              ),
              if (isCurrent)
                const AppBadge(text: 'Current', tone: AppBadgeTone.brand),
            ],
          ),
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(plan.description!, style: muted),
          ],
          const SizedBox(height: AppSpacing.md),
          // Aligned price block.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _inrFmt.format(plan.monthlyPrice),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '/month',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (plan.yearlyPrice != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_inrFmt.format(plan.yearlyPrice)} / year',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Aligned limit rows.
          _LimitRow(
            icon: Icons.school_outlined,
            label: 'Students',
            value: _limitText(plan.maxStudents),
          ),
          _LimitRow(
            icon: Icons.sports_outlined,
            label: 'Coaches',
            value: _limitText(plan.maxCoaches),
          ),
          _LimitRow(
            icon: Icons.location_city_outlined,
            label: 'Centers',
            value: _limitText(plan.maxCenters),
          ),
          if (!isCurrent) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
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

  String _limitText(int? max) => max == null ? 'Unlimited' : max.toString();

  void _requestChange(BuildContext context, PlanRow plan) {
    AppSnackbar.info(
      context,
      "We've noted your interest in ${plan.name}. "
      'Our team will reach out to confirm the change.',
    );
  }
}

/// A single limit row inside a plan card — icon + label on the left, the
/// limit value right-aligned so cards line up for comparison.
class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A past SaaS-invoice row, styled to match the billing invoice tile:
/// tinted leading status icon → invoice# → metadata subtitle → trailing
/// amount + status badge (with an outstanding-balance cue).
class _SaasInvoiceTile extends StatelessWidget {
  const _SaasInvoiceTile({required this.invoice});
  final SaasInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);
    final tone = _tone(invoice);
    final (fg, bg) = switch (tone) {
      AppBadgeTone.success => (sem.success, sem.successContainer),
      AppBadgeTone.warning => (sem.warning, sem.warningContainer),
      AppBadgeTone.danger => (sem.danger, sem.dangerContainer),
      AppBadgeTone.info => (sem.info, sem.infoContainer),
      _ => (scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
    };
    return AppListTile(
      wrapLeading: false,
      leading: CircleAvatar(
        backgroundColor: bg,
        child: Icon(_statusIcon(invoice), color: fg, size: 18),
      ),
      title: Text(invoice.invoiceNumber),
      subtitle: Text(
        'Issued ${_dateFmt.format(invoice.issuedAt)} · '
        'due ${_dateFmt.format(invoice.dueDate)}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _inrFmt.format(invoice.totalAmount),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppBadge(text: _statusLabel(invoice), tone: tone),
        ],
      ),
    );
  }

  String _statusLabel(SaasInvoice inv) =>
      inv.balance > 0 ? 'Bal ${_inrFmt.format(inv.balance)}' : 'Paid';

  AppBadgeTone _tone(SaasInvoice inv) {
    if (inv.balance <= 0) return AppBadgeTone.success;
    return switch (inv.status.toLowerCase()) {
      'overdue' || 'past_due' => AppBadgeTone.danger,
      'partial' => AppBadgeTone.warning,
      _ => AppBadgeTone.info,
    };
  }

  IconData _statusIcon(SaasInvoice inv) {
    if (inv.balance <= 0) return Icons.check;
    return switch (inv.status.toLowerCase()) {
      'overdue' || 'past_due' => Icons.warning_amber_outlined,
      'partial' => Icons.hourglass_bottom,
      _ => Icons.description_outlined,
    };
  }
}
