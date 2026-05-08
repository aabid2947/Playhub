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
  const CheckoutFailure({required this.code, required this.message});
  final int code;
  final String message;
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
    final res = await _client.functions
        .invoke('create-razorpay-order', body: {'invoice_id': invoiceId});
    final body = res.data as Map<String, dynamic>;
    if (body['order_id'] == null) {
      throw StateError(body['error']?.toString() ?? 'order create failed');
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
        message: r.message ?? 'Payment failed',
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
