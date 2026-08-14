import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:playhub/features/billing/data/razorpay_checkout.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Provider-agnostic invoice checkout. Calls the `create-payment-order` Edge
/// Function, which picks the academy's enabled gateway (Razorpay or Paytm), then
/// opens the matching checkout — the Razorpay native sheet, or Paytm's hosted
/// payment page in a WebView. The server (webhook + `verify-paytm-payment` for
/// Paytm; webhook for Razorpay) remains the source of truth for the recorded
/// payment.
///
/// Reuses the [CheckoutResult] hierarchy from [RazorpayCheckout].
class PaymentCheckout {
  PaymentCheckout(this._client);
  final SupabaseClient _client;

  /// [context] is required to present Paytm's WebView; it is unused for the
  /// Razorpay native flow.
  Future<CheckoutResult> payInvoice({
    required BuildContext context,
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
      // Order creation failed — nothing has been charged, so a connectivity
      // failure here is safely retryable (see [CheckoutFailure.isNetwork]).
      return CheckoutFailure(
        code: -3,
        message: _humanizeOrderError(e),
        isNetwork: looksLikeNetworkError(e.toString()),
      );
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
        if (!context.mounted) {
          return const CheckoutFailure(code: -2, message: 'Could not open payment.');
        }
        return _payPaytm(context, body);
      case 'razorpay':
      default:
        final r = await _payRazorpay(
          body,
          academyName: academyName,
          prefillEmail: prefillEmail,
          prefillContact: prefillContact,
        );
        // The Razorpay sheet's "success" only means the user finished — it is
        // NOT proof of a captured charge. Confirm server-side before we report
        // success, so a payment can't be marked paid (or lost) on the client's
        // word alone. The webhook remains the async backstop.
        if (r is CheckoutSuccess) return _verifyRazorpay(r);
        return r;
    }
  }

  /// Server-side confirmation of a Razorpay charge (verify-razorpay-payment).
  /// Returns the original success only when the server reports `captured`.
  Future<CheckoutResult> _verifyRazorpay(CheckoutSuccess s) async {
    try {
      final res = await _client.functions.invoke(
        'verify-razorpay-payment',
        body: {
          'razorpay_order_id': s.orderId,
          'razorpay_payment_id': s.paymentId,
        },
      );
      final data = res.data;
      final status =
          data is Map<String, dynamic> ? data['status']?.toString() : null;
      if (status == 'captured') return s;
      if (status == null) {
        // Couldn't read a status — the webhook will reconcile it.
        return const CheckoutFailure(
          code: -5,
          message: "Payment is being confirmed — we'll update once it clears.",
        );
      }
      return CheckoutFailure(code: -1, message: 'Payment not completed ($status).');
    } on Object {
      // Verify call failed (e.g. network). Don't claim success; the webhook
      // backstop still records a genuine capture.
      return const CheckoutFailure(
        code: -5,
        message: "Payment is being confirmed — we'll update shortly.",
      );
    }
  }

  /// Owner self-serve SaaS subscription checkout. Calls `create-saas-order`
  /// (which issues a SaaS invoice + a Razorpay order on PlayHub's PLATFORM
  /// keys), opens the Razorpay sheet, then CONFIRMS the charge server-side via
  /// `verify-saas-payment` (verify-on-return) — so a captured payment activates
  /// the academy even if the async platform webhook never fires. A
  /// [CheckoutSuccess] returned here means the server confirmed `captured`.
  Future<CheckoutResult> paySaasSubscription({
    required String academyName,
    String planCode = 'starter',
    String? prefillEmail,
    String? prefillContact,
  }) async {
    final Map<String, dynamic> body;
    try {
      final res = await _client.functions
          .invoke('create-saas-order', body: {'plan_code': planCode});
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        return const CheckoutFailure(
          code: -3,
          message: 'Could not start payment. Please try again.',
        );
      }
      body = data;
    } on Object catch (e) {
      // Order creation failed — nothing has been charged, so a connectivity
      // failure here is safely retryable (see [CheckoutFailure.isNetwork]).
      return CheckoutFailure(
        code: -3,
        message: _humanizeOrderError(e),
        isNetwork: looksLikeNetworkError(e.toString()),
      );
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

    final saasInvoiceId = body['invoice_id'] as String?;
    final result = await _payRazorpay(
      body,
      academyName: academyName,
      prefillEmail: prefillEmail,
      prefillContact: prefillContact,
    );
    // Never trust the client sheet's "success" alone (invariant #6): confirm
    // the charge server-side, which ALSO records it if the platform webhook
    // never fired — the failure that left an academy stuck on trial.
    if (result is CheckoutSuccess && saasInvoiceId != null) {
      return _verifySaas(result, saasInvoiceId);
    }
    return result;
  }

  /// Server-side confirmation of a SaaS Razorpay charge (verify-saas-payment).
  /// Returns the original success only when the server reports `captured`.
  Future<CheckoutResult> _verifySaas(
    CheckoutSuccess s,
    String saasInvoiceId,
  ) async {
    try {
      final res = await _client.functions.invoke(
        'verify-saas-payment',
        body: {
          'saas_invoice_id': saasInvoiceId,
          'razorpay_order_id': s.orderId,
          'razorpay_payment_id': s.paymentId,
        },
      );
      final data = res.data;
      final status =
          data is Map<String, dynamic> ? data['status']?.toString() : null;
      if (status == 'captured') return s;
      if (status == null) {
        return const CheckoutFailure(
          code: -5,
          message: "Payment is being confirmed — we'll update once it clears.",
        );
      }
      return CheckoutFailure(
        code: -1,
        message: 'Payment not completed ($status).',
      );
    } on Object {
      return const CheckoutFailure(
        code: -5,
        message: "Payment is being confirmed — we'll update shortly.",
      );
    }
  }

  // --- Razorpay (native sheet) ------------------------------------------------

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
      final message = sanitizeCheckoutMessage(r.message);
      resolve(CheckoutFailure(
        code: r.code ?? -1,
        // The sheet couldn't reach the gateway — the user was never charged,
        // so this is retryable like an order-creation failure.
        isNetwork: looksLikeNetworkError(message),
        message: message,
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

  // --- Paytm (hosted page in a WebView) --------------------------------------

  Future<CheckoutResult> _payPaytm(
    BuildContext context,
    Map<String, dynamic> body,
  ) async {
    final mid = body['mid'] as String;
    final orderId = body['order_id'] as String;
    final txnToken = body['txn_token'] as String;
    final callbackUrl = body['callback_url'] as String;
    final isStaging = body['is_staging'] as bool? ?? false;

    final host = isStaging
        ? 'https://securegw-stage.paytm.in'
        : 'https://securegw.paytm.in';
    final payPageUrl =
        '$host/theia/api/v1/showPaymentPage?mid=$mid&orderId=$orderId';

    // Open Paytm's hosted page; it POSTs the result back to our callbackUrl,
    // which we detect to close the WebView. (The query is stripped so we match
    // regardless of the params Paytm appends.)
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PaytmWebView(
          payPageUrl: payPageUrl,
          mid: mid,
          orderId: orderId,
          txnToken: txnToken,
          callbackUrlPrefix: callbackUrl.split('?').first,
        ),
      ),
    );

    // Whether the user completed or backed out, the server is authoritative.
    final status = await _verifyPaytm(orderId);
    switch (status) {
      case 'TXN_SUCCESS':
        return CheckoutSuccess(paymentId: '', orderId: orderId, signature: null);
      case 'PENDING':
        return const CheckoutFailure(
          code: -5,
          message: "Payment is processing — we'll update once it's confirmed.",
        );
      default:
        return const CheckoutFailure(
          code: -1,
          message: 'Payment was not completed.',
        );
    }
  }

  /// Asks the server to confirm a Paytm order against the Transaction-Status
  /// API and record it if paid. Returns the authoritative status string.
  Future<String> _verifyPaytm(String orderId) async {
    try {
      final res = await _client.functions
          .invoke('verify-paytm-payment', body: {'order_id': orderId});
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return data['status']?.toString() ?? 'UNKNOWN';
      }
    } on Object {
      // Fall through — treat as unknown; the webhook still reconciles.
    }
    return 'UNKNOWN';
  }
}

/// Hosts Paytm's hosted payment page. POSTs `mid`/`orderId`/`txnToken` to the
/// `showPaymentPage` endpoint, and pops when Paytm redirects to our callback.
class _PaytmWebView extends StatefulWidget {
  const _PaytmWebView({
    required this.payPageUrl,
    required this.mid,
    required this.orderId,
    required this.txnToken,
    required this.callbackUrlPrefix,
  });

  final String payPageUrl;
  final String mid;
  final String orderId;
  final String txnToken;
  final String callbackUrlPrefix;

  @override
  State<_PaytmWebView> createState() => _PaytmWebViewState();
}

class _PaytmWebViewState extends State<_PaytmWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith(widget.callbackUrlPrefix)) {
              // Payment flow finished — close before loading the callback JSON.
              if (mounted) Navigator.of(context).maybePop(true);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.parse(widget.payPageUrl),
        method: LoadRequestMethod.post,
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: Uint8List.fromList(
          utf8.encode(
            'mid=${Uri.encodeQueryComponent(widget.mid)}'
            '&orderId=${Uri.encodeQueryComponent(widget.orderId)}'
            '&txnToken=${Uri.encodeQueryComponent(widget.txnToken)}',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paytm'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(false),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
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
