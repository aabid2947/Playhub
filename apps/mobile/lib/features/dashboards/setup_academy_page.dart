import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Shown when the signed-in user is an academy_owner with no academy yet
/// (e.g. arrived after email verification, or completed signup before the
/// bootstrap step ran).
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
      setState(() => _error = 'Name required');
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Set up your academy',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                "You're signed in but have no academy yet. "
                'Give yours a name to finish setup.',
              ),
              const SizedBox(height: AppSpacing.xl),
              AppFormField(
                controller: _name,
                label: 'Academy name',
                hint: 'e.g. Elite Cricket Academy',
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: AppSemanticColors.of(context).danger),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _busy ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create academy'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
