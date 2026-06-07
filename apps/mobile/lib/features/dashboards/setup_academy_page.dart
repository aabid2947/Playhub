import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/auth_scaffold.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Content never grows wider than this — keeps the form readable on tablet and
/// web while staying full-bleed on a phone. Mirrors the auth frame's max width.
const double _maxContentWidth = 440;

/// Shown when the signed-in user is an academy_owner with no academy yet
/// (e.g. arrived after email verification, or completed signup before the
/// bootstrap step ran).
///
/// Rendered as the body of the `role_dashboard` "Welcome" scaffold, so this
/// widget is intentionally **app-bar-less** — it provides the scrolling body
/// only, reusing the auth-screen frame ([BrandMark] + [AuthMessage]) so
/// onboarding feels continuous with sign-up.
class SetupAcademyPage extends ConsumerStatefulWidget {
  const SetupAcademyPage({super.key});

  @override
  ConsumerState<SetupAcademyPage> createState() => _SetupAcademyPageState();
}

class _SetupAcademyPageState extends ConsumerState<SetupAcademyPage> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name for your academy to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await bootstrapOwnerAcademy(ref, name);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        'Set up your academy',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        "You're signed in but don't have an academy yet. "
                        'This is the only step — name your academy and we '
                        'create your workspace so you can start adding centers, '
                        'coaches and students.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      if (_error != null) ...[
                        AuthMessage(message: _error!, isError: true),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      AppFormField(
                        controller: _name,
                        label: 'Academy name',
                        hint: 'e.g. Elite Cricket Academy',
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_busy) _go();
                        },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton(
                        onPressed: _busy ? null : _go,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Create academy'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
