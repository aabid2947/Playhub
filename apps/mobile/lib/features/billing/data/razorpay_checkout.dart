import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess({
    required this.paymentId,
    required this.orderId,
    required this.signature,
  });
  final String paymentId;
  final String orderId;
  final String? signature;
}

class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure({
    required this.code,
    required this.message,
    this.isNetwork = false,
  });
  final int code;
  final String message;

  /// True only when the failure was connectivity (no internet / DNS / timeout)
  /// **before any charge could have been made** — i.e. creating the order or
  /// opening the sheet. Callers use this to offer a retry instead of a dead
  /// end. A failure while CONFIRMING a charge is never flagged here: the money
  /// may already have moved, so retrying payment would be wrong.
  final bool isNetwork;
}

class CheckoutExternalWallet extends CheckoutResult {
  const CheckoutExternalWallet({required this.walletName});
  final String walletName;
}

/// One-shot Razorpay checkout per call. Construct, [payInvoice], done.
class RazorpayCheckout {
  RazorpayCheckout(this._client);
  final SupabaseClient _client;

  Future<CheckoutResult> payInvoice({
    required String invoiceId,
    required String academyName,
    String? prefillEmail,
    String? prefillContact,
  }) async {
    final Map<String, dynamic> body;
    try {
      final res = await _client.functions
          .invoke('create-razorpay-order', body: {'invoice_id': invoiceId});
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        return const CheckoutFailure(
          code: -3,
          message: 'Could not start payment. Please try again.',
        );
      }
      body = data;
    } on Object catch (e) {
      return CheckoutFailure(
        code: -3,
        message: _humanizeOrderError(e),
      );
    }
    if (body['order_id'] == null) {
      // Edge function reported a business-rule failure (e.g. invoice already
      // paid, attempt cap reached). Surface its short message if usable.
      final raw = body['error']?.toString() ?? '';
      return CheckoutFailure(
        code: -4,
        message: raw.isEmpty || raw.length > 140
            ? 'Could not start payment. Please try again.'
            : raw,
      );
    }
    final orderId = body['order_id'] as String;
    final keyId = body['key_id'] as String;
    final amountPaise = (body['amount_paise'] as num).toInt();
    final invoiceNumber = body['invoice_number'] as String;

    final razorpay = Razorpay();
    final completer = Completer<CheckoutResult>();
    void resolve(CheckoutResult r) {
      if (!completer.isCompleted) completer.complete(r);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      resolve(CheckoutSuccess(
        paymentId: r.paymentId ?? '',
        orderId: r.orderId ?? '',
        signature: r.signature,
      ));
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      resolve(CheckoutFailure(
        code: r.code ?? -1,
        message: sanitizeCheckoutMessage(r.message),
      ));
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      resolve(CheckoutExternalWallet(walletName: r.walletName ?? 'wallet'));
    });

    try {
      razorpay.open(<String, dynamic>{
        'key': keyId,
        'order_id': orderId,
        'amount': amountPaise,
        'currency': 'INR',
        'name': academyName,
        'description': 'Invoice $invoiceNumber',
        if (prefillEmail != null || prefillContact != null)
          'prefill': {
            if (prefillEmail != null) 'email': prefillEmail,
            if (prefillContact != null) 'contact': prefillContact,
          },
        'theme': {'color': '#1565C0'},
        'retry': {'enabled': false},
      });
    } catch (e) {
      resolve(CheckoutFailure(code: -2, message: 'Failed to open: $e'));
    }

    try {
      return await completer.future;
    } finally {
      razorpay.clear();
    }
  }
}

/// Whether [text] (an exception, or a gateway's failure message) reads as a
/// connectivity problem rather than a declined/cancelled payment. Shared by
/// both checkout paths so "no internet" is recognised identically everywhere.
bool looksLikeNetworkError(String text) {
  final s = text.toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('no address associated') ||
      s.contains('connection refused') ||
      s.contains('connection closed') ||
      s.contains('network') ||
      s.contains('offline') ||
      s.contains('unreachable') ||
      s.contains('timed out') ||
      s.contains('timeout');
}

/// Razorpay's native bridge occasionally hands back the literal string
/// "undefined" (or "null") instead of a real description — seen on
/// cancelled/interrupted checkouts where the JS side never populated one.
/// Treat those the same as a genuinely missing message.
String sanitizeCheckoutMessage(String? raw) {
  final trimmed = raw?.trim() ?? '';
  final lower = trimmed.toLowerCase();
  if (trimmed.isEmpty || lower == 'undefined' || lower == 'null') {
    return 'Payment failed. Please try again.';
  }
  return trimmed;
}

String _humanizeOrderError(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network')) {
    return 'Network error. Please check your connection.';
  }
  if (s.contains('timed out') || s.contains('timeout')) {
    return 'The request timed out. Please try again.';
  }
  return 'Could not start payment. Please try again.';
}
