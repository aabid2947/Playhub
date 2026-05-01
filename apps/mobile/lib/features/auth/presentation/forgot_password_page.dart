import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _message = 'Enter a valid email';
        _isError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
    });
    try {
      // Web bounces back to the current origin; native opens the app via
      // the `ai.ghostmap.playhub://login-callback` URL scheme registered
      // in iOS Info.plist + Android manifest.
      final redirectTo = kIsWeb
          ? Uri.base.origin
          : 'ai.ghostmap.playhub://login-callback';
      await ref.read(supabaseClientProvider).auth.resetPasswordForEmail(
            email,
            redirectTo: redirectTo,
          );
      setState(() => _message =
          'If an account exists for $email, a reset link has been sent.');
    } on AuthException catch (e) {
      setState(() {
        _message = e.message;
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Enter the email tied to your account and we will send a '
              'password-reset link.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(color: _isError ? Colors.red : Colors.green),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send reset link'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
