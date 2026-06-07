import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/billing/presentation/discount_structures_page.dart';
import 'package:playhub/features/billing/presentation/fee_structures_page.dart';
import 'package:playhub/features/billing/presentation/financial_reports_page.dart';
import 'package:playhub/features/billing/presentation/invoice_list_page.dart';
import 'package:playhub/features/billing/presentation/payments_list_page.dart';

/// Pushed full page that owns the single AppBar + TabBar for billing.
///
/// The five destinations are grouped by concern rather than presented as five
/// flat peers: **Money** (transactional — invoices/payments) and **Setup**
/// (configuration — fees/discounts) each host an in-tab segmented sub-nav, and
/// **Reports** stands alone. All five child pages remain reachable and render
/// as app-bar-less bodies inside this page's TabBarView.
class BillingDashboardPage extends StatelessWidget {
  const BillingDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Billing'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Money'),
              Tab(text: 'Setup'),
              Tab(text: 'Reports'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SegmentedSection(
              segments: [
                _BillingSegment(label: 'Invoices', child: InvoiceListPage()),
                _BillingSegment(label: 'Payments', child: PaymentsListPage()),
              ],
            ),
            _SegmentedSection(
              segments: [
                _BillingSegment(label: 'Fees', child: FeeStructuresPage()),
                _BillingSegment(
                  label: 'Discounts',
                  child: DiscountStructuresPage(),
                ),
              ],
            ),
            FinancialReportsPage(),
          ],
        ),
      ),
    );
  }
}

/// One destination within a grouped tab: a [label] for the segmented control
/// and the app-bar-less [child] page it reveals.
class _BillingSegment {
  const _BillingSegment({required this.label, required this.child});

  final String label;
  final Widget child;
}

/// Hosts two or more [segments] under a single tab, toggled by a Material
/// [SegmentedButton]. The selected child stays alive via an [IndexedStack] so
/// switching segments preserves each list's scroll/filter state.
class _SegmentedSection extends StatefulWidget {
  const _SegmentedSection({required this.segments});

  final List<_BillingSegment> segments;

  @override
  State<_SegmentedSection> createState() => _SegmentedSectionState();
}

class _SegmentedSectionState extends State<_SegmentedSection> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: [
                for (var i = 0; i < widget.segments.length; i++)
                  ButtonSegment<int>(
                    value: i,
                    label: Text(widget.segments[i].label),
                  ),
              ],
              selected: {_index},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _index = selection.first),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              for (final segment in widget.segments) segment.child,
            ],
          ),
        ),
      ],
    );
  }
}
