import 'package:flutter/material.dart';

/// Shown when a payment could not START because the device had no usable
/// connection — driven by `CheckoutFailure.isNetwork`, which is set only for
/// failures that happen *before* any charge is possible (creating the order, or
/// the gateway sheet failing to reach the network).
///
/// The point is that a dropped connection must never be a dead end: the user is
/// told plainly that nothing was charged and gets a one-tap retry, instead of a
/// snackbar that leaves them wondering whether money moved.
///
/// Returns true when the user asked to try again.
///
/// Deliberately NOT used for a failure while *confirming* a charge — there the
/// money may already have moved, so we keep the existing "payment is being
/// confirmed, we'll update shortly" message and let the webhook reconcile.
Future<bool> showPaymentOfflineDialog(
  BuildContext context, {
  required String message,
  String retryLabel = 'Try again',
  String closeLabel = 'Close',
}) async {
  final retry = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.wifi_off_rounded),
      title: const Text('No internet connection'),
      content: Text(
        '$message\n\n'
        "You haven't been charged. Reconnect and try again.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(closeLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(retryLabel),
        ),
      ],
    ),
  );
  return retry ?? false;
}
