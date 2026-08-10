import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/auth_scaffold.dart';
import 'package:playhub/features/billing/data/payment_checkout.dart';
import 'package:playhub/features/billing/data/razorpay_checkout.dart';
import 'package:playhub/features/billing/presentation/payment_offline_dialog.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Content never grows wider than this — keeps the form readable on tablet and
/// web while staying full-bleed on a phone. Mirrors the auth frame's max width.
const double _maxContentWidth = 440;

final _inrFmt =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Compact "500 students · 20 coaches · 3 centers" line from a plan's caps.
/// Null when the plan sets no caps (unlimited), so the caller can fall back to
/// the plan's own description.
String? _planLimits(int? students, int? coaches, int? centers) {
  final parts = <String>[
    if (students != null) '$students students',
    if (coaches != null) '$coaches coaches',
    if (centers != null) '$centers center${centers == 1 ? '' : 's'}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// One selectable plan row (free trial or a paid plan) — a bordered card that
/// highlights when picked, with a radio glyph for affordance.
class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.title,
    required this.price,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String price;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.06)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: AppType.heavy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                price,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: AppType.heavy,
                  color: selected ? scheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
  String? _error;

  /// `code` of the chosen paid plan, or null for the 14-day free trial (the
  /// default — nobody gets charged by accidentally hitting Continue).
  String? _planCode;

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

  /// Continue with whatever is selected: the free trial, or checkout for the
  /// chosen paid plan.
  Future<void> _submit() async {
    final code = _planCode;
    if (code == null) return _go();
    return _subscribe(code);
  }

  /// Create the academy, then immediately open Razorpay for the chosen plan.
  /// We call the bootstrap RPC directly (not [bootstrapOwnerAcademy]) so the
  /// currentProfile invalidation is DEFERRED until after checkout — otherwise
  /// the role dashboard would rebuild and unmount this page mid-payment. The
  /// academy is created on a trial either way, so a cancelled/failed payment
  /// just lands the owner in the app on their free trial.
  Future<void> _subscribe(String planCode) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name for your academy to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final client = ref.read(supabaseClientProvider);
    var academyCreated = false;
    try {
      // 1. Create the academy (subscription auto-created as a 14-day trial).
      await client.rpc<dynamic>(
        'bootstrap_owner_academy',
        params: {'p_academy_name': name},
      );
      academyCreated = true;

      // 2. Open the Razorpay sheet for the plan the owner picked.
      Future<CheckoutResult> startCheckout() =>
          PaymentCheckout(client).paySaasSubscription(
            academyName: name,
            planCode: planCode,
            prefillEmail: client.auth.currentUser?.email,
          );
      var result = await startCheckout();

      // Offline before the charge could start: the academy already exists on
      // its free trial, so offer a retry rather than silently dumping them into
      // the app. Declining continues on the trial (the dashboard carries an
      // Upgrade card, and Settings → Plans & subscription is always there).
      while (result is CheckoutFailure && result.isNetwork) {
        if (!mounted) return;
        final retry = await showPaymentOfflineDialog(
          context,
          message: result.message,
          closeLabel: 'Continue on free trial',
        );
        if (!retry) break;
        result = await startCheckout();
      }
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
      // A network failure BEFORE the academy exists leaves the owner on this
      // screen — keep them here with an inline, retryable message instead of a
      // snackbar that scrolls away (the Continue button is the retry).
      if (!academyCreated && looksLikeNetworkError(e.toString())) {
        if (mounted) {
          setState(
            () => _error = 'No internet connection. Reconnect and tap '
                'Continue again — nothing has been charged.',
          );
        }
      } else if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      // Once the academy exists, refresh so the role dashboard routes the owner
      // into the app (active if paid, else trial). If bootstrap itself failed
      // we deliberately DON'T refresh — that would re-fetch over the same dead
      // connection and replace this screen's retry message with an error page.
      if (academyCreated) {
        ref
          ..invalidate(currentProfileProvider)
          ..invalidate(mySubscriptionProvider);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plansAsync = ref.watch(availablePlansProvider);
    final plans = plansAsync.valueOrNull ?? const [];
    final selected = plans.where((p) => p.code == _planCode).firstOrNull;
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
                          if (!_busy) _submit();
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        AuthMessage(message: _error!, isError: true),
                      ],

                      // ── Plan choice ───────────────────────────────────────
                      // Every active plan is listed alongside the free trial,
                      // so the owner picks from the real price list instead of
                      // the old two hardcoded buttons.
                      const SizedBox(height: AppSpacing.xl),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Choose a plan',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: AppType.heavy),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _PlanOption(
                        title: '14-day free trial',
                        price: 'Free',
                        subtitle: '1 sport · 1 coach · 2 batches · 5 students',
                        selected: _planCode == null,
                        onTap: _busy
                            ? null
                            : () => setState(() => _planCode = null),
                      ),
                      if (plansAsync.isLoading) ...[
                        const SizedBox(height: AppSpacing.md),
                        const AppLoading(),
                      ],
                      for (final p in plans) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _PlanOption(
                          title: p.name,
                          price: '${_inrFmt.format(p.monthlyPrice)}/month',
                          subtitle: _planLimits(p.maxStudents, p.maxCoaches,
                                  p.maxCenters) ??
                              p.description ??
                              'Full access',
                          selected: _planCode == p.code,
                          onTap: _busy
                              ? null
                              : () => setState(() => _planCode = p.code),
                        ),
                      ],

                      const SizedBox(height: AppSpacing.xl),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                selected == null
                                    ? 'Start 14-day free trial'
                                    : 'Subscribe — '
                                        '${_inrFmt.format(selected.monthlyPrice)}'
                                        '/month',
                              ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        selected == null
                            ? 'No card needed for the trial. You can upgrade '
                                'anytime from Settings → Plans & subscription.'
                            : "You'll pay securely via Razorpay. You can change "
                                'your plan anytime from Settings → Plans & '
                                'subscription.',
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
