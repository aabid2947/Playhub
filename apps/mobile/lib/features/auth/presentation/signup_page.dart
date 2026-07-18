import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/presentation/auth_scaffold.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _academyName = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _academyName.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
    });
    try {
      final client = ref.read(supabaseClientProvider);
      // Pass role + names + intended academy in user metadata. The
      // handle_new_auth_user trigger reads first_name/last_name/role; the
      // academy itself is created later via bootstrap_owner_academy().
      final res = await client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {
          'role': 'academy_owner',
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'academy_name': _academyName.text.trim(),
        },
      );

      if (res.session != null) {
        // Email confirmation disabled — bootstrap right away.
        await client.rpc<dynamic>(
          'bootstrap_owner_academy',
          params: {'p_academy_name': _academyName.text.trim()},
        );
        if (mounted) context.go('/home');
      } else {
        setState(
          () => _message =
              'Account created. Verify your email, then sign in to finish setup.',
        );
      }
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
      title: 'Create your academy',
      subtitle: "You'll be the owner — set it up in a minute.",
      onBack: () => context.go('/login'),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppFormField(
                controller: _academyName,
                label: 'Academy name',
                hint: 'e.g. Elite Cricket Academy',
                prefixIcon: const Icon(Icons.sports_outlined),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppFormField(
                      controller: _firstName,
                      label: 'First name',
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppFormField(
                      controller: _lastName,
                      label: 'Last name',
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppFormField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(Icons.mail_outline),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Valid email required'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _password,
                label: 'Password',
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                validator: (v) =>
                    (v == null || v.length < 8) ? 'At least 8 characters' : null,
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.lg),
          AuthMessage(message: _message!, isError: _isError),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _busy ? null : _signUp,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create academy'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ],
    );
  }
}
