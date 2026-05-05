/// Lifecycle status of an invoice.
enum InvoiceStatus {
  draft('draft', 'Draft'),
  issued('issued', 'Issued'),
  partial('partial', 'Partial'),
  paid('paid', 'Paid'),
  overdue('overdue', 'Overdue'),
  cancelled('cancelled', 'Cancelled');

  const InvoiceStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static InvoiceStatus fromDb(String? v) {
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return InvoiceStatus.issued;
  }
}

class Invoice {
  const Invoice({
    required this.id,
    required this.academyId,
    required this.studentId,
    required this.invoiceNumber,
    required this.status,
    required this.dueDate,
    required this.baseAmount,
    required this.taxAmount,
    required this.lateFeeAmount,
    required this.amount,
    required this.amountPaid,
    required this.issuedAt,
    this.feeStructureId,
    this.periodStart,
    this.periodEnd,
    this.notes,
  });

  factory Invoice.fromMap(Map<String, dynamic> m) => Invoice(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        studentId: m['student_id'] as String,
        feeStructureId: m['fee_structure_id'] as String?,
        invoiceNumber: m['invoice_number'] as String,
        status: InvoiceStatus.fromDb(m['status'] as String?),
        dueDate: DateTime.parse(m['due_date'] as String),
        issuedAt: DateTime.parse(m['issued_at'] as String),
        periodStart: m['period_start'] == null
            ? null
            : DateTime.parse(m['period_start'] as String),
        periodEnd: m['period_end'] == null
            ? null
            : DateTime.parse(m['period_end'] as String),
        baseAmount: (m['base_amount'] as num).toDouble(),
        taxAmount: (m['tax_amount'] as num).toDouble(),
        lateFeeAmount: (m['late_fee_amount'] as num).toDouble(),
        amount: (m['amount'] as num).toDouble(),
        amountPaid: (m['amount_paid'] as num).toDouble(),
        notes: m['notes'] as String?,
      );

  final String id;
  final String academyId;
  final String studentId;
  final String? feeStructureId;
  final String invoiceNumber;
  final InvoiceStatus status;
  final DateTime dueDate;
  final DateTime issuedAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final double baseAmount;
  final double taxAmount;
  final double lateFeeAmount;
  final double amount;
  final double amountPaid;
  final String? notes;

  double get balance => amount - amountPaid;
}

class InvoiceLineItem {
  const InvoiceLineItem({
    required this.id,
    required this.invoiceId,
    required this.kind,
    required this.description,
    required this.quantity,
    required this.unitAmount,
    required this.totalAmount,
  });

  factory InvoiceLineItem.fromMap(Map<String, dynamic> m) => InvoiceLineItem(
        id: m['id'] as String,
        invoiceId: m['invoice_id'] as String,
        kind: m['kind'] as String,
        description: m['description'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        unitAmount: (m['unit_amount'] as num).toDouble(),
        totalAmount: (m['total_amount'] as num).toDouble(),
      );

  final String id;
  final String invoiceId;
  final String kind; // base | tax | late_fee | discount | adjustment
  final String description;
  final double quantity;
  final double unitAmount;
  final double totalAmount;
}
