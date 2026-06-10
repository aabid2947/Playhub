import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart'
    show PlanRow;
import 'package:playhub/shared/widgets/widgets.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _inrFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

/// Academy-owner facing subscription management — v1 "Sports-Light",
/// archetype C (pushed detail under a NAVY billing hero).
/// - Navy hero shows the current plan + status [AppBadge]/glass chips and a
///   translucent [AppHeroStatRow] (price · cycle · renewal).
/// - Lists available plans with upgrade/downgrade requests, gated on
///   [Capabilities.manageSubscription] (owner-only; RLS is the real gate).
/// - Lists past saas_invoices (paid + outstanding).
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
    final caps = ref.watch(capabilitiesProvider);

    void refresh() => ref
      ..invalidate(mySubscriptionProvider)
      ..invalidate(mySaasInvoicesProvider)
      ..invalidate(availablePlansProvider);

    final sub = subAsync.valueOrNull;
    final plan =
        plansAsync.valueOrNull?.where((p) => p.id == sub?.planId).firstOrNull;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => refresh(),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Navy billing hero ────────────────────────────────────────
            _Hero(
              sub: sub,
              plan: plan,
              loading: subAsync.isLoading,
              onBack: () => Navigator.of(context).pop(),
              onRefresh: refresh,
            ),
            // Body overlaps the hero band upward, v1-style.
            Transform.translate(
              offset: const Offset(0, -AppSpacing.xl),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Current plan facts ──────────────────────────────
                    subAsync.when(
                      loading: () => const AppCard(child: AppLoading()),
                      error: (e, _) => AppErrorView(
                        message: friendlyError(e),
                        onRetry: () =>
                            ref.invalidate(mySubscriptionProvider),
                      ),
                      data: (sub) {
                        if (sub == null) {
                          return const AppCard(
                            child: AppEmptyState(
                              icon: Icons.workspace_premium_outlined,
                              title: 'No subscription on file',
                              subtitle:
                                  'Your academy is not on a billing plan '
                                  'yet. Our team will reach out to set one '
                                  'up.',
                            ),
                          );
                        }
                        return _CurrentPlanCard(sub: sub, plan: plan);
                      },
                    ),

                    // ── Plans ───────────────────────────────────────────
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Plans',
                      icon: Icons.sell_outlined,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    plansAsync.when(
                      loading: () => const AppLoading(),
                      error: (e, _) => AppErrorView(
                        message: friendlyError(e),
                        onRetry: () =>
                            ref.invalidate(availablePlansProvider),
                      ),
                      data: (plans) {
                        if (plans.isEmpty) {
                          return const AppCard(
                            child: AppEmptyState(
                              icon: Icons.sell_outlined,
                              title: 'No plans available',
                              subtitle:
                                  'There are no active plans to compare '
                                  'right now.',
                            ),
                          );
                        }
                        final currentPlanId = subAsync.valueOrNull?.planId;
                        return Column(
                          children: [
                            for (final p in plans)
                              _PlanCard(
                                plan: p,
                                isCurrent: p.id == currentPlanId,
                                canManage: caps.manageSubscription,
                              ),
                          ],
                        );
                      },
                    ),

                    // ── Past invoices ───────────────────────────────────
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Past invoices',
                      icon: Icons.receipt_long_outlined,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    invoicesAsync.when(
                      loading: () => const AppLoading(),
                      error: (e, _) => AppErrorView(
                        message: friendlyError(e),
                        onRetry: () =>
                            ref.invalidate(mySaasInvoicesProvider),
                      ),
                      data: (rows) {
                        if (rows.isEmpty) {
                          return const AppCard(
                            child: AppEmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: 'No invoices yet',
                              subtitle:
                                  'Your subscription invoices will appear '
                                  'here.',
                            ),
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
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Archetype-C navy billing hero: back + refresh circle buttons, the current
/// plan name, a status [AppBadge] + cycle glass chip, and a translucent
/// [AppHeroStatRow] summarising price · cycle · renewal. Falls back to a
/// neutral "No plan" treatment when the academy has no subscription on file.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.sub,
    required this.plan,
    required this.loading,
    required this.onBack,
    required this.onRefresh,
  });

  final AcademySubscription? sub;
  final PlanRow? plan;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (badgeLabel, badgeTone) =
        sub == null ? ('No plan', AppBadgeTone.neutral) : _statusBadge(sub!);
    final planName = sub == null
        ? 'No subscription'
        : (plan?.name ?? 'Unknown plan');

    return AppGradientHeader(
      colors: AppPalette.navyGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: onBack,
              ),
              const Spacer(),
              AppCircleIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onTap: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Subscription',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: AppType.semibold,
              letterSpacing: AppType.trackingWide,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  planName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: AppType.heavy,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppBadge(text: badgeLabel, tone: badgeTone),
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppHeroStatRow(
              stats: [
                (
                  _heroPrice(sub!, plan),
                  _cycleLabel(sub!.billingCycle),
                ),
                (
                  _dateFmt.format(sub!.currentPeriodEnd),
                  sub!.cancelledAt != null ? 'Active until' : 'Renews on',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The headline price for the hero stat — matches the plan's price for the
  /// active billing cycle, falling back to the monthly price.
  String _heroPrice(AcademySubscription s, PlanRow? p) {
    if (p == null) return '—';
    final yearly = p.yearlyPrice;
    final isYearly = switch (s.billingCycle.toLowerCase()) {
      'yearly' || 'annual' || 'year' => true,
      _ => false,
    };
    if (isYearly && yearly != null) return _inrFmt.format(yearly);
    return _inrFmt.format(p.monthlyPrice);
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

/// Plan facts card sitting under the hero — the plan description plus the key
/// billing dates (cycle / renewal / trial / cancellation) as aligned rows.
class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.sub, required this.plan});
  final AcademySubscription sub;
  final PlanRow? plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (plan?.description != null && plan!.description!.isNotEmpty) ...[
            Text(
              plan!.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
          ],
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
/// cards line up vertically and read as a comparison. The current plan is
/// highlighted with a brand-light card tint + "Current" badge; other plans
/// offer a gated "Request change" action ([Capabilities.manageSubscription]).
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.canManage,
  });
  final PlanRow plan;
  final bool isCurrent;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      // Tint the current plan brand-light so it reads as selected without
      // re-implementing the card's border.
      color: isCurrent
          ? AppPalette.brandPrimary.withValues(alpha: 0.06)
          : null,
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
          // Plan-change requests are owner-only (RLS is the real gate); the
          // button only shows for managers on a non-current plan.
          if (!isCurrent && canManage) ...[
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
