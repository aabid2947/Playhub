/// A per-academy payment gateway configuration, as exposed by the
/// `academy_payment_gateway_status` view. Mirrors the secure backend model:
/// the secret itself is NEVER returned to the client — only whether one is
/// configured. See migration 20260615000000_academy_payment_gateways.sql.
class PaymentGateway {
  const PaymentGateway({
    required this.provider,
    this.keyId,
    this.isEnabled = false,
    this.secretConfigured = false,
    this.webhookConfigured = false,
    this.config = const <String, dynamic>{},
    this.secretSetAt,
    this.updatedAt,
  });

  factory PaymentGateway.fromMap(Map<String, dynamic> m) => PaymentGateway(
        provider: m['provider'] as String,
        keyId: m['key_id'] as String?,
        isEnabled: (m['is_enabled'] as bool?) ?? false,
        secretConfigured: (m['secret_configured'] as bool?) ?? false,
        webhookConfigured: (m['webhook_configured'] as bool?) ?? false,
        config: (m['config'] as Map?)?.cast<String, dynamic>() ?? const {},
        secretSetAt: m['secret_set_at'] == null
            ? null
            : DateTime.tryParse(m['secret_set_at'].toString()),
        updatedAt: m['updated_at'] == null
            ? null
            : DateTime.tryParse(m['updated_at'].toString()),
      );

  /// 'razorpay' | 'paytm'.
  final String provider;

  /// Public merchant identifier (Razorpay key_id / Paytm MID). Not secret.
  final String? keyId;

  /// Whether this gateway is the active one used to charge in the academy.
  final bool isEnabled;

  /// Whether an API secret is stored in Vault (the value itself is never sent).
  final bool secretConfigured;

  /// Whether a webhook signing secret is stored (Razorpay only).
  final bool webhookConfigured;

  /// Non-secret provider config. Paytm: `website`, `environment` (stage|prod).
  final Map<String, dynamic> config;

  final DateTime? secretSetAt;
  final DateTime? updatedAt;

  /// Paytm website name (e.g. "DEFAULT" / "WEBSTAGING"); null for Razorpay.
  String? get website => config['website'] as String?;

  /// Paytm environment: 'stage' | 'prod'; null for Razorpay.
  String? get environment => config['environment'] as String?;

  /// Ready to be enabled for checkout: needs both a key id and a stored secret.
  /// Paytm additionally needs a website + environment.
  bool get isConfigured {
    final base = (keyId?.isNotEmpty ?? false) && secretConfigured;
    if (provider == kPaytmProvider) {
      return base &&
          (website?.isNotEmpty ?? false) &&
          (environment == 'stage' || environment == 'prod');
    }
    return base;
  }
}

/// The providers PlayHub supports today. (`paytm` is stored + manageable now;
/// its live checkout flow ships in a follow-up — Razorpay is wired end-to-end.)
const kRazorpayProvider = 'razorpay';
const kPaytmProvider = 'paytm';
