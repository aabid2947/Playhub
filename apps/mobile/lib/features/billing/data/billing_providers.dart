import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/features/billing/data/payment.dart';

// =============================================================================
// Fee structures
// =============================================================================

final feeStructuresProvider =
    FutureProvider<List<FeeStructure>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('fee_structures')
      .select()
      .eq('academy_id', academyId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => FeeStructure.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<FeeStructure> createFeeStructure(
  WidgetRef ref,
  Map<String, dynamic> data,
) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) throw StateError('No academy linked to current user');
  final row = await client
      .from('fee_structures')
      .insert({...data, 'academy_id': academyId})
      .select()
      .single();
  ref.invalidate(feeStructuresProvider);
  return FeeStructure.fromMap(row);
}

Future<FeeStructure> updateFeeStructure(
  WidgetRef ref,
  String id,
  Map<String, dynamic> patch,
) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('fee_structures')
      .update(patch)
      .eq('id', id)
      .select()
      .single();
  ref.invalidate(feeStructuresProvider);
  return FeeStructure.fromMap(row);
}

// =============================================================================
// Invoices
// =============================================================================

class InvoiceFilter {
  const InvoiceFilter({this.status, this.studentId});
  final InvoiceStatus? status;
  final String? studentId;
}

final invoiceFilterProvider =
    StateProvider<InvoiceFilter>((_) => const InvoiceFilter());

final invoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];
  final filter = ref.watch(invoiceFilterProvider);

  final client = ref.read(supabaseClientProvider);
  var query =
      client.from('invoices').select().eq('academy_id', academyId);
  if (filter.status != null) {
    query = query.eq('status', filter.status!.dbValue);
  }
  if (filter.studentId != null) {
    query = query.eq('student_id', filter.studentId!);
  }
  final rows = await query.order('issued_at', ascending: false);
  return (rows as List)
      .map((r) => Invoice.fromMap(r as Map<String, dynamic>))
      .toList();
});

final invoiceLineItemsProvider = FutureProvider.family<
    List<InvoiceLineItem>, String>((ref, invoiceId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('invoice_line_items')
      .select()
      .eq('invoice_id', invoiceId)
      .order('created_at');
  return (rows as List)
      .map((r) => InvoiceLineItem.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<Invoice> createInvoice(
  WidgetRef ref, {
  required String studentId,
  required double baseAmount,
  required DateTime dueDate,
  String? feeStructureId,
  double taxAmount = 0,
  String? notes,
}) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) throw StateError('No academy linked');

  final number = await client.rpc<dynamic>(
    'next_invoice_number',
    params: {'p_academy_id': academyId},
  );

  final row = await client
      .from('invoices')
      .insert({
        'academy_id': academyId,
        'student_id': studentId,
        'fee_structure_id': feeStructureId,
        'invoice_number': number as String,
        'status': 'issued',
        'due_date': dueDate.toIso8601String().substring(0, 10),
        'base_amount': baseAmount,
        'tax_amount': taxAmount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      })
      .select()
      .single();

  await client.from('invoice_line_items').insert([
    {
      'invoice_id': row['id'],
      'academy_id': academyId,
      'kind': 'base',
      'description': 'Fee',
      'quantity': 1,
      'unit_amount': baseAmount,
    },
    if (taxAmount > 0)
      {
        'invoice_id': row['id'],
        'academy_id': academyId,
        'kind': 'tax',
        'description': 'Tax',
        'quantity': 1,
        'unit_amount': taxAmount,
      },
  ]);

  ref.invalidate(invoicesProvider);
  return Invoice.fromMap(row);
}

Future<Invoice> updateInvoice(
  WidgetRef ref,
  String id,
  Map<String, dynamic> patch,
) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('invoices')
      .update(patch)
      .eq('id', id)
      .select()
      .single();
  ref.invalidate(invoicesProvider);
  return Invoice.fromMap(row);
}

// =============================================================================
// Payments + refunds
// =============================================================================

final paymentsForInvoiceProvider =
    FutureProvider.family<List<Payment>, String>((ref, invoiceId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('payments')
      .select()
      .eq('invoice_id', invoiceId)
      .order('paid_at', ascending: false);
  return (rows as List)
      .map((r) => Payment.fromMap(r as Map<String, dynamic>))
      .toList();
});

final refundsForPaymentProvider =
    FutureProvider.family<List<Refund>, String>((ref, paymentId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('refunds')
      .select()
      .eq('payment_id', paymentId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => Refund.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<Payment> recordManualPayment(
  WidgetRef ref, {
  required Invoice invoice,
  required double amount,
  required PaymentMethod method,
  String? notes,
  DateTime? paidAt,
}) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final row = await client
      .from('payments')
      .insert({
        'academy_id': invoice.academyId,
        'invoice_id': invoice.id,
        'student_id': invoice.studentId,
        'amount': amount,
        'method': method.dbValue,
        'status': 'completed',
        'recorded_by': profile?.id,
        if (paidAt != null) 'paid_at': paidAt.toUtc().toIso8601String(),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      })
      .select()
      .single();
  ref
    ..invalidate(invoicesProvider)
    ..invalidate(paymentsForInvoiceProvider(invoice.id));
  return Payment.fromMap(row);
}

/// Wraps the `process-refund` Edge Function.
Future<void> requestRefund(
  WidgetRef ref, {
  required String paymentId,
  required double amount,
  String? reason,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client.functions.invoke(
    'process-refund',
    body: {
      'payment_id': paymentId,
      'amount': amount,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    },
  );
  ref
    ..invalidate(invoicesProvider)
    ..invalidate(refundsForPaymentProvider(paymentId));
}

/// Wraps `create-razorpay-order`. Returns the order payload for the
/// client SDK; for now (no parent login) admins copy the order_id and
/// share manually.
Future<Map<String, dynamic>> createRazorpayOrder(
  WidgetRef ref,
  String invoiceId,
) async {
  final client = ref.read(supabaseClientProvider);
  final res = await client.functions.invoke(
    'create-razorpay-order',
    body: {'invoice_id': invoiceId},
  );
  return Map<String, dynamic>.from(res.data as Map);
}

/// Wraps `generate-invoice-pdf` — returns a signed CSV URL.
Future<String> generateInvoiceReceipt(
  WidgetRef ref,
  String invoiceId,
) async {
  final client = ref.read(supabaseClientProvider);
  final res = await client.functions.invoke(
    'generate-invoice-pdf',
    body: {'invoice_id': invoiceId},
  );
  final data = Map<String, dynamic>.from(res.data as Map);
  return data['signed_url'] as String;
}
