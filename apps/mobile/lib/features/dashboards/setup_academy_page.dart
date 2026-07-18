import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/auth_scaffold.dart';
import 'package:playhub/features/billing/data/payment_checkout.dart';
import 'package:playhub/features/billing/data/razorpay_checkout.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Content never grows wider than this — keeps the form readable on tablet and
/// web while staying full-bleed on a phone. Mirrors the auth frame's max width.
const double _maxContentWidth = 440;

/// Shown when the signed-in user is an academy_owner with no academy yet
/// (e.g. arrived after email verification, or completed signup before the
/// bootstrap step ran).
///
/// Rendered as the body of the `role_dashboard` "Welcome" scaffold, so this
/// widget is intentionally **app-bar-less** — it provides the scrolling body
/// only, reusing the auth-screen frame ([BrandMark] + [AuthMessage]) so
/// onboarding feels continuous with sign-up.
class SetupAcademyPage extends ConsumerStatefulWidget {
  const SetupAcademyPage({super.key});

  @override
  ConsumerState<SetupAcademyPage> createState() => _SetupAcademyPageState();
}

class _SetupAcademyPageState extends ConsumerState<SetupAcademyPage> {
  final _name = TextEditingController();
  bool _busy = false;
  bool _pendingSubscribe = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Carry over the academy name captured at signup (stashed in user_metadata
    // by signup_page). Owners who signed up with email confirmation ON reach
    // this screen only after verifying + signing in, so without this they'd
    // retype the name they already entered. They still choose trial vs
    // subscribe below; the field stays editable.
    final raw = ref
        .read(supabaseClientProvider)
        .auth
        .currentUser
        ?.userMetadata?['academy_name'];
    if (raw is String && raw.trim().isNotEmpty) {
      _name.text = raw.trim();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name for your academy to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await bootstrapOwnerAcademy(ref, name);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Create the academy, then immediately open Razorpay for the ₹100/mo plan.
  /// We call the bootstrap RPC directly (not [bootstrapOwnerAcademy]) so the
  /// currentProfile invalidation is DEFERRED until after checkout — otherwise
  /// the role dashboard would rebuild and unmount this page mid-payment. The
  /// academy is created on a trial either way, so a cancelled/failed payment
  /// just lands the owner in the app on their free trial.
  Future<void> _subscribe() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name for your academy to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _pendingSubscribe = true;
      _error = null;
    });

    final client = ref.read(supabaseClientProvider);
    try {
      // 1. Create the academy (subscription auto-created as a 14-day trial).
      await client.rpc<dynamic>(
        'bootstrap_owner_academy',
        params: {'p_academy_name': name},
      );

      // 2. Open the Razorpay sheet for the ₹100/mo Starter plan.
      final result = await PaymentCheckout(client).paySaasSubscription(
        academyName: name,
        prefillEmail: client.auth.currentUser?.email,
      );
      if (!mounted) return;

      switch (result) {
        case CheckoutSuccess():
          AppSnackbar.success(
            context,
            'Payment received — activating your subscription…',
          );
        case CheckoutFailure(:final message):
          AppSnackbar.info(
            context,
            message.isEmpty
                ? "Payment not completed — you're on your 14-day free trial. "
                    'Upgrade anytime from Settings.'
                : message,
          );
        case CheckoutExternalWallet():
          AppSnackbar.info(context, 'Payment is processing.');
      }
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      // Whatever happened, the academy now exists — refresh so the role
      // dashboard routes the owner into the app (active if paid, else trial).
      ref
        ..invalidate(currentProfileProvider)
        ..invalidate(mySubscriptionProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        'Set up your academy',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        "You're signed in but don't have an academy yet. "
                        'This is the only step — name your academy and we '
                        'create your workspace so you can start adding centers, '
                        'coaches and students.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      AppFormField(
                        controller: _name,
                        label: 'Academy name',
                        hint: 'e.g. Elite Cricket Academy',
                        autofocus: true,
                        prefixIcon: const Icon(Icons.sports_outlined),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_busy) _go();
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        AuthMessage(message: _error!, isError: true),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      // Primary: pay now (₹100/mo). Opens Razorpay.
                      FilledButton(
                        onPressed: _busy ? null : _subscribe,
                        child: _busy && _pendingSubscribe
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Subscribe — ₹100/month'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Secondary: start the free trial (no payment).
                      OutlinedButton(
                        onPressed: _busy ? null : _go,
                        child: _busy && !_pendingSubscribe
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Start 14-day free trial'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Your free trial includes 1 sport, 1 coach and up to '
                        '5 students. Subscribe anytime to unlock more.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
