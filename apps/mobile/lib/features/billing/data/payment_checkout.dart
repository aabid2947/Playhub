import 'dart:async';

import 'package:paytm_allinone_sdk/paytm_allinone_sdk.dart';
import 'package:playhub/features/billing/data/razorpay_checkout.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider-agnostic invoice checkout. Calls the `create-payment-order` Edge
/// Function, which picks the academy's enabled gateway (Razorpay or Paytm), then
/// opens the matching SDK. The server (webhook / status confirmation) remains the
/// source of truth for the recorded payment — a [CheckoutSuccess] only means the
/// SDK reported success; the invoice updates once the webhook lands.
///
/// Reuses the [CheckoutResult] hierarchy from [RazorpayCheckout].
class PaymentCheckout {
  PaymentCheckout(this._client);
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
          .invoke('create-payment-order', body: {'invoice_id': invoiceId});
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        return const CheckoutFailure(
          code: -3,
          message: 'Could not start payment. Please try again.',
        );
      }
      body = data;
    } on Object catch (e) {
      return CheckoutFailure(code: -3, message: _humanizeOrderError(e));
    }

    if (body['order_id'] == null) {
      final raw = body['error']?.toString() ?? '';
      return CheckoutFailure(
        code: -4,
        message: raw.isEmpty || raw.length > 140
            ? 'Could not start payment. Please try again.'
            : raw,
      );
    }

    final provider = body['provider'] as String? ?? 'razorpay';
    switch (provider) {
      case 'paytm':
        return _payPaytm(body);
      case 'razorpay':
      default:
        return _payRazorpay(
          body,
          academyName: academyName,
          prefillEmail: prefillEmail,
          prefillContact: prefillContact,
        );
    }
  }

  // --- Razorpay ---------------------------------------------------------------

  Future<CheckoutResult> _payRazorpay(
    Map<String, dynamic> body, {
    required String academyName,
    String? prefillEmail,
    String? prefillContact,
  }) async {
    final orderId = body['order_id'] as String;
    final keyId = body['key_id'] as String;
    final amountPaise = (body['amount_paise'] as num).toInt();
    final invoiceNumber = body['invoice_number'] as String? ?? '';

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

  // --- Paytm ------------------------------------------------------------------

  Future<CheckoutResult> _payPaytm(Map<String, dynamic> body) async {
    final mid = body['mid'] as String;
    final orderId = body['order_id'] as String;
    final txnToken = body['txn_token'] as String;
    final amount = body['amount'] as String; // rupees, e.g. "500.00"
    final callbackUrl = body['callback_url'] as String;
    final isStaging = body['is_staging'] as bool? ?? false;

    try {
      final response = await AllInOneSdk.startTransaction(
        mid,
        orderId,
        amount,
        txnToken,
        callbackUrl,
        isStaging,
        // restrictAppInvoke=false → allow the Paytm app; enableAssist=true →
        // in-SDK assist screen.
        false,
        true,
      );
      final status = response?['STATUS']?.toString() ?? '';
      if (status == 'TXN_SUCCESS') {
        return CheckoutSuccess(
          paymentId: response?['TXNID']?.toString() ?? '',
          orderId: response?['ORDERID']?.toString() ?? orderId,
          signature: null,
        );
      }
      return CheckoutFailure(
        code: -1,
        message: response?['RESPMSG']?.toString() ?? 'Payment failed',
      );
    } on Object catch (e) {
      // The SDK throws on cancellation / errors (often a PlatformException).
      return CheckoutFailure(code: -1, message: _humanizePaytmError(e));
    }
  }
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

String _humanizePaytmError(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('cancel')) return 'Payment cancelled.';
  if (s.contains('network')) return 'Network error. Please check your connection.';
  return 'Payment could not be completed.';
}
