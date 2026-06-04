import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create your academy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Sign up to create a new sports academy. You will be the owner.',
              ),
              const SizedBox(height: AppSpacing.xl),
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
                obscureText: true,
                textInputAction: TextInputAction.done,
                prefixIcon: const Icon(Icons.lock_outline),
                validator: (v) => (v == null || v.length < 8)
                    ? 'At least 8 characters'
                    : null,
              ),
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _message!,
                  style: TextStyle(color: _isError ? Colors.red : Colors.green),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
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
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
