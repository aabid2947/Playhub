import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/payment_gateways/data/payment_gateway.dart';

/// The current academy's payment gateways, keyed by provider. Reads the
/// secret-free `academy_payment_gateway_status` view (RLS restricts this to the
/// academy owner). Empty for non-owners / unconfigured academies.
final paymentGatewaysProvider =
    FutureProvider<Map<String, PaymentGateway>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return const {};

  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('academy_payment_gateway_status')
      .select()
      .eq('academy_id', academyId);

  final map = <String, PaymentGateway>{};
  for (final r in rows as List) {
    final g = PaymentGateway.fromMap(r as Map<String, dynamic>);
    map[g.provider] = g;
  }
  return map;
});

/// Save/replace a gateway's credentials. Secrets are write-only: pass `null`
/// for [apiSecret]/[webhookSecret] to keep the stored value unchanged (e.g.
/// when only toggling [enabled] or editing the key id). The secret is sent to
/// the `set_payment_gateway` RPC, which stores it in Vault server-side; it is
/// never read back. RLS + the RPC enforce owner-only.
Future<void> savePaymentGateway(
  WidgetRef ref, {
  required String provider,
  required String keyId,
  required bool enabled,
  String? apiSecret,
  String? webhookSecret,
  Map<String, dynamic>? config,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client.rpc<void>(
    'set_payment_gateway',
    params: {
      'p_provider': provider,
      'p_key_id': keyId,
      'p_api_secret': apiSecret,
      'p_webhook_secret': webhookSecret,
      'p_enabled': enabled,
      'p_config': config,
    },
  );
  ref.invalidate(paymentGatewaysProvider);
}

/// Toggle whether a (already-configured) gateway is the active one for
/// checkout, without touching its stored secrets.
Future<void> setPaymentGatewayEnabled(
  WidgetRef ref, {
  required String provider,
  required String keyId,
  required bool enabled,
}) =>
    savePaymentGateway(
      ref,
      provider: provider,
      keyId: keyId,
      enabled: enabled,
    );

/// Remove a gateway and delete its Vault secrets.
Future<void> clearPaymentGateway(WidgetRef ref, String provider) async {
  final client = ref.read(supabaseClientProvider);
  await client.rpc<void>(
    'clear_payment_gateway',
    params: {'p_provider': provider},
  );
  ref.invalidate(paymentGatewaysProvider);
}
