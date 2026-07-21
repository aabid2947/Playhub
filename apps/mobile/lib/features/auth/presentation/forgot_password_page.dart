import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/presentation/auth_scaffold.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
      // the `ai.playhub://login-callback` URL scheme registered
      // in iOS Info.plist + Android manifest.
      final redirectTo = kIsWeb
          ? Uri.base.origin
          : 'ai.playhub://login-callback';
      await ref.read(supabaseClientProvider).auth.resetPasswordForEmail(
            email,
            redirectTo: redirectTo,
          );
      setState(() => _message =
          'If an account exists for $email, a reset link has been sent.');
    } on Object catch (e) {
      setState(() {
        _message = friendlyError(e);
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset password',
      subtitle: "Enter your account email and we'll send a secure reset link.",
      onBack: () => context.go('/login'),
      children: [
        AppFormField(
          controller: _email,
          label: 'Email',
          hint: 'you@academy.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          prefixIcon: const Icon(Icons.mail_outline),
          onFieldSubmitted: (_) => _busy ? null : _send(),
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.xs),
          AuthMessage(message: _message!, isError: _isError),
        ],
        const SizedBox(height: AppSpacing.lg),
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
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
