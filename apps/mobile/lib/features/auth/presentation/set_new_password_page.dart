import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/auth_recovery.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reached only via the password-recovery deep link. The Supabase SDK
/// parses the URL fragment, establishes a recovery session, and the
/// auth-state listener flips [recoveryActiveProvider] which the router
/// uses to land here.
class SetNewPasswordPage extends ConsumerStatefulWidget {
  const SetNewPasswordPage({super.key});

  @override
  ConsumerState<SetNewPasswordPage> createState() =>
      _SetNewPasswordPageState();
}

class _SetNewPasswordPageState extends ConsumerState<SetNewPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() {
        _message = 'Password must be at least 8 characters';
        _isError = true;
      });
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() {
        _message = 'Passwords do not match';
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
      await ref
          .read(supabaseClientProvider)
          .auth
          .updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      ref.read(recoveryActiveProvider.notifier).state = false;
      setState(() => _message = 'Password updated. Sign in to continue.');
      // Sign out so the user re-authenticates with the new password.
      await ref.read(supabaseClientProvider).auth.signOut();
      if (mounted) context.go('/login');
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
      appBar: AppBar(title: const Text('Set new password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Pick a new password (at least 8 characters). You will be '
              'signed out after; sign in again with the new one.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
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
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update password'),
            ),
          ],
        ),
      ),
    );
  }
}
