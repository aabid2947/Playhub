enum PaymentMethod {
  razorpay('razorpay', 'Razorpay'),
  cash('cash', 'Cash'),
  cheque('cheque', 'Cheque'),
  bankTransfer('bank_transfer', 'Bank transfer'),
  upiManual('upi_manual', 'UPI (manual)');

  const PaymentMethod(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static PaymentMethod fromDb(String? v) {
    for (final m in values) {
      if (m.dbValue == v) return m;
    }
    return PaymentMethod.cash;
  }
}

class Payment {
  const Payment({
    required this.id,
    required this.academyId,
    required this.invoiceId,
    required this.studentId,
    required this.amount,
    required this.method,
    required this.status,
    required this.paidAt,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.recordedBy,
    this.notes,
  });

  factory Payment.fromMap(Map<String, dynamic> m) => Payment(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        invoiceId: m['invoice_id'] as String,
        studentId: m['student_id'] as String,
        amount: (m['amount'] as num).toDouble(),
        method: PaymentMethod.fromDb(m['method'] as String?),
        status: m['status'] as String,
        razorpayOrderId: m['razorpay_order_id'] as String?,
        razorpayPaymentId: m['razorpay_payment_id'] as String?,
        recordedBy: m['recorded_by'] as String?,
        paidAt: DateTime.parse(m['paid_at'] as String),
        notes: m['notes'] as String?,
      );

  final String id;
  final String academyId;
  final String invoiceId;
  final String studentId;
  final double amount;
  final PaymentMethod method;
  final String status;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? recordedBy;
  final DateTime paidAt;
  final String? notes;
}

class Refund {
  const Refund({
    required this.id,
    required this.academyId,
    required this.paymentId,
    required this.amount,
    required this.status,
    this.reason,
    this.razorpayRefundId,
    this.processedAt,
  });

  factory Refund.fromMap(Map<String, dynamic> m) => Refund(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        paymentId: m['payment_id'] as String,
        amount: (m['amount'] as num).toDouble(),
        status: m['status'] as String,
        reason: m['reason'] as String?,
        razorpayRefundId: m['razorpay_refund_id'] as String?,
        processedAt: m['processed_at'] == null
            ? null
            : DateTime.parse(m['processed_at'] as String),
      );

  final String id;
  final String academyId;
  final String paymentId;
  final double amount;
  final String status;
  final String? reason;
  final String? razorpayRefundId;
  final DateTime? processedAt;
}
