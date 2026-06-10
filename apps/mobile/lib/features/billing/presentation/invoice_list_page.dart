import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/features/billing/presentation/invoice_detail_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

/// The four in-body status pills, in display order. Each maps to the
/// [InvoiceStatus] (or `null` for "All") fed into [invoiceFilterProvider], so
/// the pills drive the same server-side filter the list already used. "Pending"
/// is an issued-but-unpaid invoice ([InvoiceStatus.issued]).
const _statusTabs = <(String, InvoiceStatus?)>[
  ('All', null),
  ('Paid', InvoiceStatus.paid),
  ('Overdue', InvoiceStatus.overdue),
  ('Pending', InvoiceStatus.issued),
];

/// Tab body under the billing dashboard — the parent page owns the AppBar +
/// TabBar, so this screen is intentionally app-bar-less. v1 "Sports-Light",
/// archetype B (list): a compact in-body header (count [AppBadge]) + an
/// [AppPillTabs] status filter above a column of invoice [AppCard]s.
class InvoiceListPage extends ConsumerWidget {
  const InvoiceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final byId = {for (final s in students) s.id: s};

    final filter = ref.watch(invoiceFilterProvider);
    // Resolve the active filter back to a pill index; any status the pills
    // don't surface (partial/draft/cancelled) reads as "All".
    final selectedIndex = _statusTabs.indexWhere((t) => t.$2 == filter.status);
    final pillIndex = selectedIndex < 0 ? 0 : selectedIndex;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: AppPillTabs(
              tabs: [for (final t in _statusTabs) t.$1],
              index: pillIndex,
              onChanged: (i) =>
                  ref.read(invoiceFilterProvider.notifier).state =
                      InvoiceFilter(status: _statusTabs[i].$2),
            ),
          ),
          Expanded(
            child: invoicesAsync.when(
              loading: () => const AppSkeletonList(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(invoicesProvider),
              ),
              data: (invoices) {
                if (invoices.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No invoices yet',
                    subtitle:
                        'Recurring invoices generate via cron when fees are '
                        'assigned.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(invoicesProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xs,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    itemCount: invoices.length + 1,
                    separatorBuilder: (_, i) => i == 0
                        ? const SizedBox.shrink()
                        : const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _ResultCount(count: invoices.length);
                      }
                      final invoice = invoices[i - 1];
                      return _InvoiceCard(
                        invoice: invoice,
                        student: byId[invoice.studentId],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact in-body header: a count [AppBadge] so the filtered result size is
/// always visible above the list.
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppSectionHeader(
        title: 'Invoices',
        trailing: AppBadge(text: count == 1 ? '1' : '$count'),
      ),
    );
  }
}

/// One invoice row as an [AppCard]: a status-toned icon tile → invoice number →
/// a tight student · due-date line → the ₹ amount with a status [AppBadge].
/// Overdue rows get a danger-toned due date so aging is scannable without
/// opening the detail page.
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, required this.student});
  final Invoice invoice;
  final Student? student;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);
    final tone = _tone(invoice.status);
    final (fg, bg) = switch (tone) {
      AppBadgeTone.success => (sem.success, sem.successContainer),
      AppBadgeTone.warning => (sem.warning, sem.warningContainer),
      AppBadgeTone.danger => (sem.danger, sem.dangerContainer),
      AppBadgeTone.info => (sem.info, sem.infoContainer),
      _ => (scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
    };

    final isOverdue = invoice.status == InvoiceStatus.overdue;
    final dueLabel = 'Due ${_dateFmt.format(invoice.dueDate)}';

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailPage(invoiceId: invoice.id),
        ),
      ),
      child: AppListTile(
        wrapLeading: false,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(_statusIcon(invoice.status), color: fg, size: 20),
        ),
        title: Text(
          invoice.invoiceNumber,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: student?.fullName ?? 'Unknown student'),
              const TextSpan(text: '  •  '),
              TextSpan(
                text: dueLabel,
                style: isOverdue
                    ? TextStyle(color: sem.danger, fontWeight: AppType.semibold)
                    : null,
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${invoice.amount.toStringAsFixed(0)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppBadge(text: invoice.status.label, tone: tone),
          ],
        ),
      ),
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

  IconData _statusIcon(InvoiceStatus s) => switch (s) {
        InvoiceStatus.paid => Icons.check,
        InvoiceStatus.partial => Icons.hourglass_bottom,
        InvoiceStatus.overdue => Icons.warning_amber_outlined,
        InvoiceStatus.cancelled => Icons.cancel_outlined,
        InvoiceStatus.draft => Icons.drafts_outlined,
        InvoiceStatus.issued => Icons.description_outlined,
      };
}
