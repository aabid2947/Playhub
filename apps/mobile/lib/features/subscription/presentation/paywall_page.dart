import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/features/subscription/presentation/subscription_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Full-screen block shown to an academy owner/admin when the academy's
/// subscription is frozen — suspended/cancelled, or an expired trial. The rest
/// of the app stays read-only (RLS is the real gate); this replaces the
/// management shell until the academy renews.
///
/// Recovery today is super-admin-applied (record a SaaS payment → auto-react-
/// ivate, or the Reactivate action); owner self-serve SaaS checkout is a
/// fast-follow. The "refresh" button re-reads the subscription so the screen
/// clears itself the moment access is restored.
class PaywallPage extends ConsumerWidget {
  const PaywallPage({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(supabaseClientProvider).auth.signOut();
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sub = ref.watch(mySubscriptionProvider).valueOrNull;
    final isTrial = sub?.isTrial ?? false;
    final title =
        isTrial ? 'Your free trial has ended' : 'Your subscription is paused';
    final message = isTrial
        ? 'Your trial is over. Renew your plan to keep managing students, '
            'coaches, batches, fees, and everything else. Your data is safe.'
        : 'Access to academy management is paused until your subscription is '
            'renewed. Your data is safe and stays available to view.';

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context, ref),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('View plans & invoices'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const SubscriptionPage()),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("I've renewed — refresh"),
                  onPressed: () => ref.invalidate(mySubscriptionProvider),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Need help renewing? Contact PlayHub support.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
