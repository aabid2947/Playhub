import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/subscription/presentation/subscription_page.dart';

/// Shared "you've hit a free-plan limit" prompt, shown when ANY free-trial usage
/// quota is reached (sports / coaches / students / batches / staff logins).
///
/// Role-aware: only the academy owner can manage the plan
/// ([Capabilities.manageSubscription]), so they get a "View plans" action that
/// opens [SubscriptionPage]; everyone else (admins, center_admins) is told to
/// ask the owner rather than being sent to a page with no action they can take.
/// RLS is still the hard gate; this is UX only. [message] is the entity-specific
/// cap text from `TrialLimits` (e.g. `TrialLimits.sportsMessage`).
Future<void> showUpgradePrompt(
  BuildContext context, {
  required String message,
}) async {
  final viewPlans = await showDialog<bool>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final canManage = ref.watch(capabilitiesProvider).manageSubscription;
        return AlertDialog(
          icon: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Upgrade your plan'),
          content: Text(
            canManage
                ? message
                : '$message\n\nAsk your academy owner to upgrade the plan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(canManage ? 'Not now' : 'OK'),
            ),
            // Only the owner can act on the plans screen — don't send anyone
            // else to a page where every control is disabled for them.
            if (canManage)
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('View plans'),
              ),
          ],
        );
      },
    ),
  );
  if ((viewPlans ?? false) && context.mounted) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SubscriptionPage()),
    );
  }
}
