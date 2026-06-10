import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Super-admin drill-down for one academy: lifecycle/status + active toggle,
/// member/student counts, owner + contact details, and the academy's SaaS
/// invoices with a manual "record payment" path. Mirrors the web console's
/// academy detail page; all reads/writes ride the super-admin RLS.
class AcademyDetailPage extends ConsumerWidget {
  const AcademyDetailPage({
    required this.academyId,
    required this.initialName,
    super.key,
  });

  final String academyId;
  final String initialName;

  ({String label, AppBadgeTone tone}) _statusBadge(String status) {
    switch (status) {
      case 'active':
        return (label: 'Active', tone: AppBadgeTone.success);
      case 'trial':
        return (label: 'Trial', tone: AppBadgeTone.info);
      case 'past_due':
        return (label: 'Past due', tone: AppBadgeTone.warning);
      case 'suspended':
        return (label: 'Suspended', tone: AppBadgeTone.danger);
      case 'cancelled':
        return (label: 'Cancelled', tone: AppBadgeTone.neutral);
      default:
        return (label: status, tone: AppBadgeTone.neutral);
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    AcademyDetail a,
  ) async {
    final enable = !a.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(enable ? 'Enable academy?' : 'Disable academy?'),
        content: Text(
          enable
              ? 'Re-enable "${a.name}"? Its members will regain access.'
              : 'Disable "${a.name}"? Everyone in this academy will lose access '
                  'until it is re-enabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(enable ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(superAdminRepoProvider).setAcademyActive(a.id, enable);
      ref
        ..invalidate(academyDetailProvider(a.id))
        ..invalidate(allAcademiesProvider)
        ..invalidate(globalKpiProvider);
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(academyDetailProvider(academyId));
    return Scaffold(
      body: async.when(
        loading: () => const AppLoading(),
        error: (e, _) => SafeArea(
          child: AppErrorView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(academyDetailProvider(academyId)),
          ),
        ),
        data: (a) {
          final sem = AppSemanticColors.of(context);
          final df = DateFormat('dd MMM yyyy');
          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(academyDetailProvider(academyId))
                ..invalidate(academyInvoicesProvider(academyId));
            },
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Hero(
                  academy: a,
                  badge: _statusBadge(a.subscriptionStatus),
                  onBack: () => Navigator.of(context).pop(),
                ),
                // Body overlaps the hero band upward, v1-style.
                Transform.translate(
                  offset: const Offset(0, -AppSpacing.xl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: AppSpacing.md,
                          mainAxisSpacing: AppSpacing.md,
                          childAspectRatio: 1.5,
                          children: [
                            AppStatTile(
                              icon: Icons.group_outlined,
                              label: 'Members',
                              value: '${a.memberCount}',
                            ),
                            AppStatTile(
                              icon: Icons.school_outlined,
                              label: 'Students',
                              value: '${a.studentCount}',
                            ),
                            AppStatTile(
                              icon: Icons.schedule_outlined,
                              label: 'Trial ends',
                              value: a.trialEndsAt == null
                                  ? '—'
                                  : df.format(a.trialEndsAt!),
                              color: sem.info,
                            ),
                            AppStatTile(
                              icon: Icons.calendar_today_outlined,
                              label: 'Joined',
                              value: df.format(a.createdAt),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _AccessSection(
                          academy: a,
                          onToggle: () => _toggleActive(context, ref, a),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _DetailsSection(academy: a),
                        const SizedBox(height: AppSpacing.lg),
                        const AppSectionHeader(
                          title: 'SaaS invoices',
                          icon: Icons.receipt_long_outlined,
                        ),
                        _InvoicesSection(academyId: academyId),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Archetype-C entity hero for an academy: a navy gradient band with the back
/// button, the academy identity (avatar + name), status glass chips, and a
/// translucent member/student summary strip.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.academy,
    required this.badge,
    required this.onBack,
  });

  final AcademyDetail academy;
  final ({String label, AppBadgeTone tone}) badge;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(academy.name, size: 56),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      academy.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: AppType.heavy,
                      ),
                    ),
                    if (academy.location != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        academy.location!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppGlassChip(badge.label, icon: Icons.workspace_premium_outlined),
              AppGlassChip(
                academy.isActive ? 'Active' : 'Disabled',
                icon: academy.isActive
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppHeroStatRow(
            stats: [
              ('${academy.memberCount}', 'Members'),
              ('${academy.studentCount}', 'Students'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Subscription state plus the platform-access toggle (enable / disable the
/// whole academy). The toggle keeps its confirm + RLS-gated write.
class _AccessSection extends StatelessWidget {
  const _AccessSection({required this.academy, required this.onToggle});

  final AcademyDetail academy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sem = AppSemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(
          title: 'Platform access',
          icon: Icons.toggle_on_outlined,
        ),
        AppCard(
          child: Row(
            children: [
              Icon(
                academy.isActive
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
                size: 18,
                color: academy.isActive ? sem.success : sem.danger,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  academy.isActive
                      ? 'Active — members can sign in.'
                      : 'Disabled — members are locked out.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              OutlinedButton(
                onPressed: onToggle,
                child: Text(academy.isActive ? 'Disable' : 'Enable'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Owner + contact facts under a section header.
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.academy});
  final AcademyDetail academy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(
          title: 'Details',
          icon: Icons.business_outlined,
        ),
        AppCard(
          child: Column(
            children: [
              _DetailRow(
                icon: Icons.person_outline,
                label: 'Owner',
                value: academy.ownerName ?? '—',
              ),
              _DetailRow(
                icon: Icons.mail_outline,
                label: 'Owner email',
                value: academy.ownerEmail ?? academy.email ?? '—',
              ),
              _DetailRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: academy.phone ?? '—',
              ),
              _DetailRow(
                icon: Icons.place_outlined,
                label: 'Location',
                value: academy.location ?? '—',
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(value, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
        if (!last) ...[
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _InvoicesSection extends ConsumerWidget {
  const _InvoicesSection({required this.academyId});
  final String academyId;

  ({String label, AppBadgeTone tone}) _invoiceBadge(String status) {
    switch (status) {
      case 'paid':
        return (label: 'Paid', tone: AppBadgeTone.success);
      case 'past_due':
        return (label: 'Past due', tone: AppBadgeTone.danger);
      case 'issued':
        return (label: 'Issued', tone: AppBadgeTone.info);
      case 'cancelled':
        return (label: 'Cancelled', tone: AppBadgeTone.neutral);
      default:
        return (label: status, tone: AppBadgeTone.neutral);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(academyInvoicesProvider(academyId));
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final df = DateFormat('dd MMM yyyy');
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: AppLoading(),
      ),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(academyInvoicesProvider(academyId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return AppCard(
            child: Text(
              'No invoices yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _InvoiceRow(
                  row: rows[i],
                  badge: _invoiceBadge(rows[i].status),
                  money: f,
                  df: df,
                  onRecordPayment: () => _openRecordPayment(
                    context,
                    ref,
                    rows[i],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openRecordPayment(
    BuildContext context,
    WidgetRef ref,
    SaasInvoiceRow invoice,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordPaymentSheet(
        academyId: academyId,
        invoice: invoice,
      ),
    );
    if (saved ?? false) {
      ref
        ..invalidate(academyInvoicesProvider(academyId))
        ..invalidate(globalKpiProvider);
      if (context.mounted) AppSnackbar.success(context, 'Payment recorded');
    }
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.row,
    required this.badge,
    required this.money,
    required this.df,
    required this.onRecordPayment,
  });

  final SaasInvoiceRow row;
  final ({String label, AppBadgeTone tone}) badge;
  final NumberFormat money;
  final DateFormat df;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canPay = row.outstanding > 0 && row.status != 'cancelled';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.invoiceNumber,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              AppBadge(text: badge.label, tone: badge.tone),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  row.dueDate == null
                      ? 'Total ${money.format(row.totalAmount)}'
                      : 'Total ${money.format(row.totalAmount)} · due '
                          '${df.format(row.dueDate!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (row.outstanding > 0)
                Text(
                  'Outstanding ${money.format(row.outstanding)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppSemanticColors.of(context).warning,
                    fontWeight: AppType.semibold,
                  ),
                ),
            ],
          ),
          if (canPay) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: onRecordPayment,
                child: const Text('Record payment'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet to log a manual SaaS payment against an invoice. The
/// apply_saas_payment trigger reconciles the invoice server-side.
class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({required this.academyId, required this.invoice});
  final String academyId;
  final SaasInvoiceRow invoice;

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.invoice.outstanding.toStringAsFixed(0),
  );
  final _reference = TextEditingController();
  String _method = 'manual';
  bool _saving = false;
  String? _error;

  static const _methods = <({String value, String label})>[
    (value: 'manual', label: 'Manual'),
    (value: 'bank_transfer', label: 'Bank transfer'),
    (value: 'razorpay', label: 'Razorpay'),
    (value: 'free', label: 'Free / waived'),
  ];

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(superAdminRepoProvider).recordSaasPayment(
            invoiceId: widget.invoice.id,
            academyId: widget.academyId,
            amount: amount,
            method: _method,
            reference: _reference.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              title: 'Record payment · ${widget.invoice.invoiceNumber}',
            ),
            Text(
              'Outstanding ${f.format(widget.invoice.outstanding)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _amount,
              label: 'Amount (₹)',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !_saving,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String>(
              label: 'Method',
              value: _method,
              items: [
                for (final m in _methods)
                  DropdownMenuItem(value: m.value, child: Text(m.label)),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _method = v ?? 'manual'),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _reference,
              label: 'Reference (optional)',
              enabled: !_saving,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppSemanticColors.of(context).danger,
                    ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Recording…' : 'Record payment'),
            ),
          ],
        ),
      ),
    );
  }
}
