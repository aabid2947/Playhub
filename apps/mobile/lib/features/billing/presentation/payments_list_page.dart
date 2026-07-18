import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/billing/data/payment.dart';
import 'package:playhub/features/billing/presentation/invoice_detail_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// The list is hard-capped server-side; the page surfaces this cap explicitly
/// rather than silently truncating.
const _paymentsLimit = 200;

final _allPaymentsProvider = FutureProvider<List<Payment>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('payments')
      .select()
      .eq('academy_id', academyId)
      .order('paid_at', ascending: false)
      .limit(_paymentsLimit);
  return (rows as List)
      .map((r) => Payment.fromMap(r as Map<String, dynamic>))
      .toList();
});

final _dayHeaderFmt = DateFormat('EEEE, dd MMM yyyy');
final _timeFmt = DateFormat('h:mm a');

/// Payments list — v1 "Sports-Light", archetype B (list).
///
/// Tab body under the billing dashboard — the parent page owns the AppBar +
/// TabBar, so this screen is intentionally app-bar-less. A method chip filter
/// sits above date-grouped payment [AppCard] rows (₹ amount + method + time),
/// each tappable through to its invoice. The 200-row cap is surfaced honestly
/// at the foot of the list rather than via a dead pagination button.
class PaymentsListPage extends ConsumerStatefulWidget {
  const PaymentsListPage({super.key});

  @override
  ConsumerState<PaymentsListPage> createState() => _PaymentsListPageState();
}

class _PaymentsListPageState extends ConsumerState<PaymentsListPage> {
  /// `null` = "All methods". Filtering is client-side over the already-fetched
  /// (capped) list, so it never widens the result beyond the 200 cap.
  PaymentMethod? _methodFilter;

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(_allPaymentsProvider);
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final byId = {for (final s in students) s.id: s};

    return Scaffold(
      body: Column(
        children: [
          _MethodFilterBar(
            selected: _methodFilter,
            onSelected: (m) => setState(() => _methodFilter = m),
          ),
          Expanded(
            child: paymentsAsync.when(
              loading: () => const AppSkeletonList(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(_allPaymentsProvider),
              ),
              data: (payments) {
                if (payments.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.payments_outlined,
                    title: 'No payments yet',
                    subtitle:
                        'Recorded and online payments will appear here.',
                  );
                }

                final filtered = _methodFilter == null
                    ? payments
                    : payments
                        .where((p) => p.method == _methodFilter)
                        .toList();

                if (filtered.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'No ${_methodFilter!.label} payments',
                    subtitle: 'Try a different payment method filter.',
                  );
                }

                // The full (capped) set tells us whether we are at the cap;
                // the filtered set drives the visible groups.
                final groups = _groupByDay(filtered);
                final atCap = payments.length >= _paymentsLimit;

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(_allPaymentsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xs,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    itemCount: groups.length + (atCap ? 2 : 1),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _ResultCount(count: filtered.length);
                      }
                      if (atCap && i == groups.length + 1) {
                        return const _CapNotice(limit: _paymentsLimit);
                      }
                      final group = groups[i - 1];
                      return _DaySection(group: group, studentsById: byId);
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

  /// Buckets payments (already newest-first) into contiguous day groups.
  List<_DayGroup> _groupByDay(List<Payment> payments) {
    final groups = <_DayGroup>[];
    DateTime? currentKey;
    for (final p in payments) {
      final local = p.paidAt.toLocal();
      final key = DateTime(local.year, local.month, local.day);
      if (currentKey == null || key != currentKey) {
        currentKey = key;
        groups.add(_DayGroup(day: key, payments: [p]));
      } else {
        groups.last.payments.add(p);
      }
    }
    return groups;
  }
}

class _DayGroup {
  _DayGroup({required this.day, required this.payments});
  final DateTime day;
  final List<Payment> payments;
}

/// Unified single-row method filter: an "All" chip plus one chip per
/// [PaymentMethod], in one coherent [Material] surface (mirrors the events
/// status chip bar). Six methods is too many for an equal-width [AppPillTabs],
/// so this stays a horizontally scrolling brand-colored [ChoiceChip] row.
class _MethodFilterBar extends StatelessWidget {
  const _MethodFilterBar({required this.selected, required this.onSelected});

  final PaymentMethod? selected;
  final ValueChanged<PaymentMethod?> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          children: [
            _MethodChip(
              label: 'All',
              selected: selected == null,
              onSelected: () => onSelected(null),
            ),
            for (final m in PaymentMethod.values)
              _MethodChip(
                label: m.label,
                selected: selected == m,
                onSelected: () => onSelected(m),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single method filter pill, brand-colored when selected. Stays a real
/// [ChoiceChip] so widget-type finders keep resolving.
class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onSelected(),
        backgroundColor: scheme.primary.withValues(alpha: 0.10),
        selectedColor: scheme.primary,
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.primary.withValues(alpha: 0.20),
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : scheme.primary,
          fontWeight: AppType.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Compact in-body header: a count [AppBadge] so the filtered result size is
/// always visible above the list (mirrors the invoice list header).
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppSectionHeader(
        title: 'Payments',
        trailing: AppBadge(text: count == 1 ? '1' : '$count'),
      ),
    );
  }
}

/// One day's worth of payments under a date [AppSectionHeader], each rendered as
/// an [AppCard] row.
class _DaySection extends StatelessWidget {
  const _DaySection({required this.group, required this.studentsById});

  final _DayGroup group;
  final Map<String, Student> studentsById;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(title: _dayLabel(group.day)),
        for (final p in group.payments) ...[
          _PaymentCard(payment: p, student: studentsById[p.studentId]),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return _dayHeaderFmt.format(day);
  }
}

/// One payment row as an [AppCard]: a status-toned method icon tile → student
/// name → a tight method · time line → the ₹ amount with a status [AppBadge].
/// Tapping the row opens the payment's invoice (payment/refund logic untouched).
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, required this.student});

  final Payment payment;
  final Student? student;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);
    final tone = _tone(payment.status);
    final (fg, bg) = switch (tone) {
      AppBadgeTone.warning => (sem.warning, sem.warningContainer),
      AppBadgeTone.danger => (sem.danger, sem.dangerContainer),
      AppBadgeTone.info => (sem.info, sem.infoContainer),
      _ => (scheme.primary, scheme.primary.withValues(alpha: 0.12)),
    };

    // Method + time of day are the two facts that matter on the row; the date
    // already lives in the day section header, so it isn't repeated here.
    final subtitle = '${payment.method.label}  •  '
        '${_timeFmt.format(payment.paidAt.toLocal())}';

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailPage(invoiceId: payment.invoiceId),
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
          child: Icon(_methodIcon(payment.method), color: fg, size: 20),
        ),
        title: Text(
          student?.fullName ?? 'Unknown student',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${payment.amount.toStringAsFixed(0)}',
              style: theme.textTheme.titleMedium,
            ),
            if (tone != null) ...[
              const SizedBox(height: AppSpacing.xs),
              AppBadge(text: _statusLabel(payment.status), tone: tone),
            ],
          ],
        ),
      ),
    );
  }

  IconData _methodIcon(PaymentMethod m) => switch (m) {
        PaymentMethod.razorpay => Icons.bolt_outlined,
        PaymentMethod.cash => Icons.payments_outlined,
        PaymentMethod.cheque => Icons.receipt_outlined,
        PaymentMethod.bankTransfer => Icons.account_balance_outlined,
        PaymentMethod.upiManual => Icons.qr_code_2_outlined,
      };

  /// `completed` is the unremarkable happy path, so it carries no badge — only
  /// the states a finance admin needs to notice get a tone.
  AppBadgeTone? _tone(String status) => switch (status) {
        'completed' => null,
        'pending' => AppBadgeTone.warning,
        'failed' => AppBadgeTone.danger,
        'refunded' => AppBadgeTone.neutral,
        'partially_refunded' => AppBadgeTone.info,
        _ => AppBadgeTone.neutral,
      };

  String _statusLabel(String status) => switch (status) {
        'partially_refunded' => 'Partly refunded',
        _ => status[0].toUpperCase() + status.substring(1),
      };
}

/// Honest footer when the server-side cap is hit. There is no pagination query
/// behind the list, so this states the cap rather than offering a dead button.
class _CapNotice extends StatelessWidget {
  const _CapNotice({required this.limit});
  final int limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.history_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Showing the latest $limit payments. Open an invoice for its '
              'full payment history.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
