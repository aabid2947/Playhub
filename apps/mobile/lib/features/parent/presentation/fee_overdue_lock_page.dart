import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/payment_checkout.dart';
import 'package:playhub/features/parent/data/parent_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Full-screen block shown to a parent/student when a linked student has an
/// unpaid invoice past the [kFeeLockGraceDays] grace window. Replaces the
/// normal dashboard shell until the overdue balance is cleared — the only
/// action available is to pay (or sign out).
///
/// This is a UX gate, not a security boundary: RLS does not restrict reads on
/// unpaid fees, so an old build could still see data. It exists to force
/// payment before the app is usable, mirroring the owner [PaywallPage].
class FeeOverdueLockPage extends ConsumerStatefulWidget {
  const FeeOverdueLockPage({super.key});

  @override
  ConsumerState<FeeOverdueLockPage> createState() =>
      _FeeOverdueLockPageState();
}

class _FeeOverdueLockPageState extends ConsumerState<FeeOverdueLockPage> {
  String? _payingId;

  Future<void> _signOut() async {
    try {
      await ref.read(supabaseClientProvider).auth.signOut();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _payInvoice(OutstandingDues r) async {
    setState(() => _payingId = r.invoiceId);
    final client = ref.read(supabaseClientProvider);
    final profile = ref.read(currentProfileProvider).valueOrNull;
    final academy = ref.read(myAcademyProvider).valueOrNull;
    final checkout = PaymentCheckout(client);
    try {
      final result = await checkout.payInvoice(
        context: context,
        invoiceId: r.invoiceId,
        academyName: academy?.name ?? 'PlayHub',
        prefillEmail: profile?.email,
        prefillContact: profile?.phone,
      );
      if (!mounted) return;
      switch (result) {
        case CheckoutSuccess():
          AppSnackbar.success(context, 'Payment received');
          // Re-read the lock state so the screen clears itself once the
          // balance is settled (the webhook/verify updates the invoice).
          ref.invalidate(feeLockProvider);
        case CheckoutExternalWallet(:final walletName):
          AppSnackbar.info(context, 'Continuing in $walletName…');
        case CheckoutFailure(:final message):
          AppSnackbar.error(context, 'Payment failed: $message');
      }
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _payingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(feeLockProvider);
    final state = async.valueOrNull ?? FeeLockState.empty;
    final dues = state.dues;
    final busy = _payingId != null;

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: busy ? null : _signOut,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(feeLockProvider),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            const SizedBox(height: AppSpacing.md),
            Icon(
              Icons.lock_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Payment overdue',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your account is on hold because a fee has been pending for '
              'more than $kFeeLockGraceDays days. Clear the overdue amount '
              'below to unlock your dashboard.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.overdueBalance > 0)
              Center(
                child: Text(
                  '₹${state.overdueBalance.toStringAsFixed(0)}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (async.isLoading && dues.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: AppLoading(),
              )
            else
              for (final r in dues) ...[
                _OverdueInvoiceTile(
                  row: r,
                  isPaying: _payingId == r.invoiceId,
                  disabled: busy,
                  onPay: () => _payInvoice(r),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text("I've paid — refresh"),
              onPressed: busy ? null : () => ref.invalidate(feeLockProvider),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Already paid? It can take a moment to reflect. Pull to refresh, '
              'or contact your academy if the hold remains.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverdueInvoiceTile extends StatelessWidget {
  const _OverdueInvoiceTile({
    required this.row,
    required this.isPaying,
    required this.onPay,
    this.disabled = false,
  });

  final OutstandingDues row;
  final bool isPaying;
  final VoidCallback onPay;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due =
        '${row.dueDate.year}-${row.dueDate.month.toString().padLeft(2, '0')}'
        '-${row.dueDate.day.toString().padLeft(2, '0')}';
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invoice ${row.invoiceNumber}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Due $due',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: disabled ? null : onPay,
            child: isPaying
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Pay ₹${row.balance.toStringAsFixed(0)}'),
          ),
        ],
      ),
    );
  }
}
