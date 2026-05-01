import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shows a yellow strip when the signed-in user has an email but it is not
/// yet confirmed. Renders nothing when the user is verified.
class VerificationBanner extends ConsumerStatefulWidget {
  const VerificationBanner({super.key});

  @override
  ConsumerState<VerificationBanner> createState() =>
      _VerificationBannerState();
}

class _VerificationBannerState extends ConsumerState<VerificationBanner> {
  bool _resending = false;
  String? _toast;

  Future<void> _resend(String email) async {
    setState(() {
      _resending = true;
      _toast = null;
    });
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .resend(type: OtpType.signup, email: email);
      setState(() => _toast = 'Verification email sent');
    } on AuthException catch (e) {
      setState(() => _toast = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session?.user;
    if (user == null) return const SizedBox.shrink();
    if (user.emailConfirmedAt != null) return const SizedBox.shrink();
    final email = user.email;
    if (email == null) return const SizedBox.shrink();

    return Material(
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _toast ?? 'Please verify your email ($email).',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _resending ? null : () => _resend(email),
              child: _resending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Resend'),
            ),
          ],
        ),
      ),
    );
  }
}
