import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/env.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/payment_gateways/data/payment_gateway.dart';
import 'package:playhub/features/payment_gateways/data/payment_gateway_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Owner-only screen to configure the academy's own payment gateway
/// credentials (Razorpay / Paytm). Secrets are **write-only**: the owner enters
/// them, they're stored encrypted in Supabase Vault server-side, and are never
/// shown again — the UI only reports whether each is configured. Owner-exclusive
/// at the RLS layer (the [Capabilities.managePaymentGateways] flag only hides
/// the entry point).
class PaymentGatewaysPage extends ConsumerStatefulWidget {
  const PaymentGatewaysPage({super.key});

  @override
  ConsumerState<PaymentGatewaysPage> createState() =>
      _PaymentGatewaysPageState();
}

class _PaymentGatewaysPageState extends ConsumerState<PaymentGatewaysPage> {
  String? _busyProvider; // provider whose toggle is in flight

  Future<void> _toggleEnabled(PaymentGateway g, bool enabled) async {
    setState(() => _busyProvider = g.provider);
    try {
      await setPaymentGatewayEnabled(
        ref,
        provider: g.provider,
        keyId: g.keyId ?? '',
        enabled: enabled,
      );
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  Future<void> _edit(String provider, PaymentGateway? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _GatewayEditorSheet(provider: provider, existing: existing),
    );
    if ((saved ?? false) && mounted) {
      AppSnackbar.success(context, 'Payment gateway saved.');
    }
  }

  Future<void> _remove(PaymentGateway g) async {
    final ok = await confirmAction(
      context,
      title: 'Remove ${_label(g.provider)}?',
      message:
          'This deletes the stored keys and secret. Payments will fall back to '
          "PlayHub's default gateway until you reconfigure.",
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    try {
      await clearPaymentGateway(ref, g.provider);
      if (mounted) AppSnackbar.success(context, 'Removed.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(capabilitiesProvider).managePaymentGateways;
    final gatewaysAsync = ref.watch(paymentGatewaysProvider);
    final academyId = ref.watch(currentProfileProvider).valueOrNull?.academyId;
    final razorpayWebhookUrl =
        (academyId != null && academyId.isNotEmpty && Env.supabaseUrl.isNotEmpty)
            ? '${Env.supabaseUrl}/functions/v1/razorpay-webhook?academy=$academyId'
            : null;

    return Scaffold(
      body: Column(
        children: [
          _Header(onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: !canManage
                ? const AppEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'Owner only',
                    subtitle: 'Only the academy owner can manage payment '
                        'gateways.',
                  )
                : gatewaysAsync.when(
                    loading: () => const AppLoading(),
                    error: (e, _) => AppErrorView(
                      message: friendlyError(e),
                      onRetry: () => ref.invalidate(paymentGatewaysProvider),
                    ),
                    data: (gateways) => ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -AppSpacing.lg),
                          child: const _SecurityNote(),
                        ),
                        _GatewayCard(
                          provider: kRazorpayProvider,
                          gateway: gateways[kRazorpayProvider],
                          live: true,
                          webhookUrl: razorpayWebhookUrl,
                          busy: _busyProvider == kRazorpayProvider,
                          onEdit: () => _edit(
                            kRazorpayProvider,
                            gateways[kRazorpayProvider],
                          ),
                          onToggle: (v) =>
                              _toggleEnabled(gateways[kRazorpayProvider]!, v),
                          onRemove: gateways[kRazorpayProvider] == null
                              ? null
                              : () => _remove(gateways[kRazorpayProvider]!),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _GatewayCard(
                          provider: kPaytmProvider,
                          gateway: gateways[kPaytmProvider],
                          live: true,
                          busy: _busyProvider == kPaytmProvider,
                          onEdit: () =>
                              _edit(kPaytmProvider, gateways[kPaytmProvider]),
                          onToggle: (v) =>
                              _toggleEnabled(gateways[kPaytmProvider]!, v),
                          onRemove: gateways[kPaytmProvider] == null
                              ? null
                              : () => _remove(gateways[kPaytmProvider]!),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String _label(String provider) =>
    provider == kRazorpayProvider ? 'Razorpay' : 'Paytm';

/// Masks all but the last 4 chars of a public key id for display.
String _maskKeyId(String keyId) {
  if (keyId.length <= 8) return keyId;
  return '${keyId.substring(0, 8)}••••${keyId.substring(keyId.length - 4)}';
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppGradientHeader(
      colors: AppPalette.navyGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: onBack,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Payment gateways',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: AppType.heavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Use your own merchant account to collect fees. Visible only to you.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Secrets are encrypted and stored securely. For your safety they '
              "are never shown again after saving — you'll only see whether a "
              'gateway is configured.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GatewayCard extends StatelessWidget {
  const _GatewayCard({
    required this.provider,
    required this.gateway,
    required this.live,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
    required this.onRemove,
    this.webhookUrl,
  });

  final String provider;
  final PaymentGateway? gateway;
  final bool live; // is the live checkout flow wired for this provider?
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onRemove;

  /// The exact webhook URL the owner must register in their gateway dashboard
  /// (Razorpay only; Paytm's callback is configured automatically). Null hides
  /// the section (e.g. before the academy id is known).
  final String? webhookUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = gateway;
    final configured = g?.isConfigured ?? false;
    final enabled = g?.isEnabled ?? false;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppPalette.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppPalette.brandPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(provider),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: AppType.heavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _statusBadge(enabled: enabled, configured: configured),
                  ],
                ),
              ),
              if (!live) const AppBadge(text: 'Soon'),
            ],
          ),
          if (configured) ...[
            const SizedBox(height: AppSpacing.md),
            _kv(
              theme,
              provider == kRazorpayProvider ? 'Key ID' : 'Merchant ID',
              _maskKeyId(g!.keyId!),
            ),
            _kv(theme, 'Secret', 'Configured'),
            if (provider == kRazorpayProvider)
              _kv(
                theme,
                'Webhook secret',
                g.webhookConfigured ? 'Configured' : 'Not set',
              ),
            if (provider == kPaytmProvider) ...[
              _kv(theme, 'Website', g.website ?? '—'),
              _kv(
                theme,
                'Environment',
                g.environment == 'prod' ? 'Production' : 'Staging',
              ),
            ],
            // Webhook setup — only once the academy uses its OWN account, so a
            // platform-fallback academy isn't told to register a webhook it
            // doesn't need. Razorpay = manual URL + copy; Paytm = automatic.
            _WebhookSection(provider: provider, webhookUrl: webhookUrl),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Not configured. Add your keys to route fee payments through '
                'your own account.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          // "Use this gateway" toggle — only for a live, configured provider.
          if (live && configured) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use this gateway for payments'),
              subtitle: Text(
                enabled
                    ? 'Active — fee payments charge to your account.'
                    : "Off — payments use PlayHub's default gateway.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: enabled,
              onChanged: busy || onToggle == null ? null : onToggle,
            ),
          ],

          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(
                    configured ? Icons.edit_outlined : Icons.add_outlined,
                  ),
                  label: Text(configured ? 'Edit keys' : 'Configure'),
                  onPressed: busy ? null : onEdit,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: busy ? null : onRemove,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge({required bool enabled, required bool configured}) {
    if (enabled) {
      return const AppBadge(
        text: 'Active',
        tone: AppBadgeTone.success,
        icon: Icons.check_circle_outline,
      );
    }
    if (configured) {
      return const AppBadge(text: 'Configured', tone: AppBadgeTone.info);
    }
    return const AppBadge(text: 'Not set up');
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(
                k,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: AppType.semibold,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Webhook setup row. For Razorpay, shows the exact `?academy=<id>` URL the
/// owner must register in their dashboard, with a copy button. For Paytm, a note
/// that the callback is wired automatically (no dashboard step).
class _WebhookSection extends StatelessWidget {
  const _WebhookSection({required this.provider, required this.webhookUrl});

  final String provider;
  final String? webhookUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (provider == kPaytmProvider) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bolt_outlined, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Payment confirmation is handled automatically — no webhook to '
                'set up in your Paytm dashboard.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Razorpay — needs manual registration.
    final url = webhookUrl;
    if (url == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Webhook URL',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: AppType.semibold,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    url,
                    maxLines: 2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy webhook URL',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      AppSnackbar.success(context, 'Webhook URL copied');
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'In your Razorpay dashboard → Settings → Webhooks, add this URL for '
            'the payment.captured and payment.failed events, using the webhook '
            'secret above.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to enter/replace a gateway's credentials. Secret fields are
/// write-only — left blank, they keep the stored value.
class _GatewayEditorSheet extends ConsumerStatefulWidget {
  const _GatewayEditorSheet({required this.provider, required this.existing});

  final String provider;
  final PaymentGateway? existing;

  @override
  ConsumerState<_GatewayEditorSheet> createState() =>
      _GatewayEditorSheetState();
}

class _GatewayEditorSheetState extends ConsumerState<_GatewayEditorSheet> {
  late final TextEditingController _keyId =
      TextEditingController(text: widget.existing?.keyId ?? '');
  final _secret = TextEditingController();
  final _webhook = TextEditingController();
  late final TextEditingController _website =
      TextEditingController(text: widget.existing?.website ?? 'DEFAULT');
  late String _environment = widget.existing?.environment ?? 'stage';
  bool _busy = false;
  String? _error;

  bool get _isRazorpay => widget.provider == kRazorpayProvider;
  bool get _isPaytm => widget.provider == kPaytmProvider;
  bool get _alreadyConfigured => widget.existing?.secretConfigured ?? false;

  @override
  void dispose() {
    _keyId.dispose();
    _secret.dispose();
    _webhook.dispose();
    _website.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final keyId = _keyId.text.trim();
    final secret = _secret.text.trim();
    if (keyId.isEmpty) {
      setState(() => _error = 'Key ID is required.');
      return;
    }
    // First-time setup must include the secret; on edit it may stay blank.
    if (!_alreadyConfigured && secret.isEmpty) {
      setState(() => _error = 'Secret is required the first time.');
      return;
    }
    Map<String, dynamic>? config;
    if (_isPaytm) {
      final website = _website.text.trim();
      if (website.isEmpty) {
        setState(() => _error = 'Website name is required for Paytm.');
        return;
      }
      config = {'website': website, 'environment': _environment};
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await savePaymentGateway(
        ref,
        provider: widget.provider,
        keyId: keyId,
        // Keep current enabled state (false if brand-new); enabling is a
        // separate explicit toggle on the card.
        enabled: widget.existing?.isEnabled ?? false,
        apiSecret: secret.isEmpty ? null : secret,
        webhookSecret: _webhook.text.trim().isEmpty ? null : _webhook.text.trim(),
        config: config,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyHint = _isRazorpay ? 'rzp_live_xxxxxxxx' : 'Paytm MID';
    final secretHint = _alreadyConfigured
        ? 'Leave blank to keep current secret'
        : 'Enter secret';

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_label(widget.provider)} credentials',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: AppType.heavy,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppFormField(
              controller: _keyId,
              label: _isRazorpay ? 'Key ID' : 'Merchant ID (MID)',
              hint: keyHint,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _secret,
              label: _isRazorpay ? 'Key secret' : 'Merchant key',
              hint: secretHint,
              obscureText: true,
            ),
            if (_isRazorpay) ...[
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _webhook,
                label: 'Webhook secret (optional)',
                hint: widget.existing?.webhookConfigured ?? false
                    ? 'Leave blank to keep current'
                    : 'From your Razorpay webhook settings',
                obscureText: true,
              ),
            ],
            if (_isPaytm) ...[
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _website,
                label: 'Website name',
                hint: 'DEFAULT (prod) / WEBSTAGING (test)',
              ),
              const SizedBox(height: AppSpacing.md),
              AppDropdownField<String>(
                label: 'Environment',
                value: _environment,
                onChanged: (v) =>
                    setState(() => _environment = v ?? 'stage'),
                items: const [
                  DropdownMenuItem(value: 'stage', child: Text('Staging (test)')),
                  DropdownMenuItem(value: 'prod', child: Text('Production')),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppSemanticColors.of(context).danger,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
