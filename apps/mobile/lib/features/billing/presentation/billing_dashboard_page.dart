import 'package:flutter/material.dart';
import 'package:playhub/features/billing/presentation/fee_structures_page.dart';
import 'package:playhub/features/billing/presentation/financial_reports_page.dart';
import 'package:playhub/features/billing/presentation/invoice_list_page.dart';
import 'package:playhub/features/billing/presentation/payments_list_page.dart';

class BillingDashboardPage extends StatelessWidget {
  const BillingDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Billing'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Invoices'),
              Tab(text: 'Fees'),
              Tab(text: 'Payments'),
              Tab(text: 'Reports'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            InvoiceListPage(),
            FeeStructuresPage(),
            PaymentsListPage(),
            FinancialReportsPage(),
          ],
        ),
      ),
    );
  }
}
