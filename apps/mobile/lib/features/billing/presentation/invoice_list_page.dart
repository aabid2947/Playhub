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

/// Tab body under the billing dashboard — the parent page owns the AppBar +
/// TabBar, so this screen is intentionally app-bar-less.
class InvoiceListPage extends ConsumerWidget {
  const InvoiceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final byId = {for (final s in students) s.id: s};

    return Scaffold(
      body: Column(
        children: [
          const _FilterBar(),
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
                    itemCount: invoices.length + 1,
                    separatorBuilder: (_, i) => i == 0
                        ? const SizedBox.shrink()
                        : const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _ResultCount(count: invoices.length);
                      }
                      final invoice = invoices[i - 1];
                      return _InvoiceTile(
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

/// The single, unified status filter for the invoice list: an "All" chip plus
/// one chip per [InvoiceStatus], in one coherent surface so the controls never
/// read as an orphaned tag cloud.
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(invoiceFilterProvider);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            _StatusFilterChip(
              label: 'All',
              selected: filter.status == null,
              onSelected: () => ref.read(invoiceFilterProvider.notifier).state =
                  const InvoiceFilter(),
            ),
            for (final s in InvoiceStatus.values) ...[
              const SizedBox(width: AppSpacing.sm),
              _StatusFilterChip(
                label: s.label,
                selected: filter.status == s,
                onSelected: () =>
                    ref.read(invoiceFilterProvider.notifier).state =
                        InvoiceFilter(status: s),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Visible result count above the list, e.g. "12 invoices".
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        count == 1 ? '1 invoice' : '$count invoices',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.student});
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
    // The student and the due date are the two facts that matter on the row;
    // overdue invoices get a danger-toned due-date so the aging is scannable
    // without opening the detail page.
    final dueLabel = 'Due ${_dateFmt.format(invoice.dueDate)}';

    return AppListTile(
      wrapLeading: false,
      leading: CircleAvatar(
        backgroundColor: bg,
        child: Icon(_statusIcon(invoice.status), color: fg, size: 18),
      ),
      title: Text(invoice.invoiceNumber),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: student?.fullName ?? 'Unknown student'),
            const TextSpan(text: ' · '),
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
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailPage(invoiceId: invoice.id),
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
