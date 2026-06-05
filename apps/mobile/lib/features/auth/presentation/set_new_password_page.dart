import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/auth_recovery.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/auth_scaffold.dart';
import 'package:playhub/shared/widgets/widgets.dart';
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
  bool _obscure = true;
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
      final client = ref.read(supabaseClientProvider);
      await client.auth.updateUser(UserAttributes(password: _password.text));

      // Clear the must_change_password flag for invitees. Self-update RLS
      // policy on users allows id = auth.uid() updates.
      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        await client.from('users').update(
          {'must_change_password': false},
        ).eq('id', uid);
        ref.invalidate(currentProfileProvider);
      }

      if (!mounted) return;
      ref.read(recoveryActiveProvider.notifier).state = false;
      setState(() => _message = 'Password updated. Sign in to continue.');
      // Sign out so the user re-authenticates with the new password.
      await client.auth.signOut();
      if (mounted) context.go('/login');
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
      title: 'Set a new password',
      subtitle: "Choose a new password (at least 8 characters). You'll be "
          'signed out, then sign in again with the new one.',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormField(
              controller: _password,
              label: 'New password',
              obscureText: _obscure,
              prefixIcon: const Icon(Icons.lock_outline),
              textInputAction: TextInputAction.next,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _confirm,
              label: 'Confirm new password',
              obscureText: _obscure,
              prefixIcon: const Icon(Icons.lock_outline),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _busy ? null : _save(),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.md),
          AuthMessage(message: _message!, isError: _isError),
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
              : const Text('Update password'),
        ),
      ],
    );
  }
}
