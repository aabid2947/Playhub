import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/announcements/data/announcement_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Admin-only composer. Pick targets (roles / batches / centers), channels,
/// then send. Defaults: empty targets = everyone in the academy.
class AnnouncementComposerPage extends ConsumerStatefulWidget {
  const AnnouncementComposerPage({super.key});

  @override
  ConsumerState<AnnouncementComposerPage> createState() =>
      _AnnouncementComposerPageState();
}

class _AnnouncementComposerPageState
    extends ConsumerState<AnnouncementComposerPage> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _selectedRoles = <String>{};
  final _selectedBatches = <String>{};
  final _selectedCenters = <String>{};
  bool _viaPush = true;
  bool _viaEmail = false;
  bool _viaInApp = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (!_viaPush && !_viaInApp && !_viaEmail) {
      setState(() => _error = 'Pick at least one channel to send through.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(announcementsRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      final ann = await repo.draft(
        subject: _subject.text.trim(),
        body: _body.text.trim(),
        targetRoles: _selectedRoles.toList(),
        targetBatches: _selectedBatches.toList(),
        targetCenters: _selectedCenters.toList(),
        viaPush: _viaPush,
        viaEmail: _viaEmail,
        viaInApp: _viaInApp,
      );
      await repo.sendNow(ann.id);
      ref.invalidate(announcementsListProvider);
      if (mounted) {
        AppSnackbar.success(context, 'Announcement sent');
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New announcement')),
      body: profileAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(currentProfileProvider),
        ),
        data: (profile) {
          final academyId = profile?.academyId;
          if (academyId == null) {
            return const AppEmptyState(
              icon: Icons.apartment_outlined,
              title: 'No academy',
              subtitle: 'You are not linked to an academy yet.',
            );
          }
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: [
                const AppSectionHeader(title: 'Message'),
                AppFormField(
                  controller: _subject,
                  label: 'Subject *',
                  hint: 'Short, scannable headline',
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppFormField(
                  controller: _body,
                  label: 'Body *',
                  hint: 'What do you want everyone to know?',
                  maxLines: 5,
                  enabled: !_busy,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Audience'),
                const _AudienceHint(),
                const SizedBox(height: AppSpacing.md),
                _AudienceGroup(
                  label: 'Roles',
                  child: _RoleChips(
                    selected: _selectedRoles,
                    enabled: !_busy,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _AudienceGroup(
                  label: 'Batches',
                  child: _BatchPicker(
                    academyId: academyId,
                    selected: _selectedBatches,
                    enabled: !_busy,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _AudienceGroup(
                  label: 'Centers',
                  child: _CenterPicker(
                    academyId: academyId,
                    selected: _selectedCenters,
                    enabled: !_busy,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Channels'),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Push notification'),
                        subtitle: const Text('Device alert via FCM'),
                        value: _viaPush,
                        onChanged:
                            _busy ? null : (v) => setState(() => _viaPush = v),
                      ),
                      SwitchListTile(
                        title: const Text('In-app feed'),
                        subtitle: const Text('Shows in the announcements feed'),
                        value: _viaInApp,
                        onChanged:
                            _busy ? null : (v) => setState(() => _viaInApp = v),
                      ),
                      SwitchListTile(
                        title: const Text('Email'),
                        subtitle: const Text('Sent to recipients with an email'),
                        value: _viaEmail,
                        onChanged:
                            _busy ? null : (v) => setState(() => _viaEmail = v),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ErrorBanner(message: _error!),
                ],
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(_busy ? 'Sending…' : 'Send announcement'),
                    onPressed: _busy ? null : _send,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Soft info banner explaining the "empty = everyone" targeting model.
class _AudienceHint extends StatelessWidget {
  const _AudienceHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: semantics.infoContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.groups_outlined, size: 20, color: semantics.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Leave everything empty to reach everyone in the academy. '
              'Picking roles, batches or centers narrows who receives this.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labeled wrapper for one audience selector (roles / batches / centers).
class _AudienceGroup extends StatelessWidget {
  const _AudienceGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

/// Inline, dismissable-looking validation/error region (matches form error
/// styling without surfacing raw exceptions).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: semantics.dangerContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: semantics.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChips extends StatefulWidget {
  const _RoleChips({required this.selected, this.enabled = true});
  final Set<String> selected;
  final bool enabled;

  @override
  State<_RoleChips> createState() => _RoleChipsState();
}

class _RoleChipsState extends State<_RoleChips> {
  static const _roles = [
    'parent',
    'student',
    'coach',
    'head_coach',
    'center_admin',
    'academy_admin',
  ];
  static const _labels = {
    'parent': 'Parents',
    'student': 'Students',
    'coach': 'Coaches',
    'head_coach': 'Head coaches',
    'center_admin': 'Center admins',
    'academy_admin': 'Admins',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final r in _roles)
          FilterChip(
            label: Text(_labels[r] ?? r),
            selected: widget.selected.contains(r),
            onSelected: widget.enabled
                ? (sel) => setState(() {
                      if (sel) {
                        widget.selected.add(r);
                      } else {
                        widget.selected.remove(r);
                      }
                    })
                : null,
          ),
      ],
    );
  }
}

class _BatchPicker extends ConsumerWidget {
  const _BatchPicker({
    required this.academyId,
    required this.selected,
    this.enabled = true,
  });
  final String academyId;
  final Set<String> selected;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    return FutureBuilder<List<({String id, String name})>>(
      future: () async {
        final rows = await client
            .from('batches')
            .select('id, name')
            .eq('academy_id', academyId)
            .eq('is_active', true)
            .order('name');
        return [
          for (final r in rows as List)
            (id: (r as Map)['id'] as String, name: r['name'] as String),
        ];
      }(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _PickerLoading();
        }
        final options = snap.data ?? const [];
        if (options.isEmpty) {
          return const _PickerEmpty(message: 'No active batches.');
        }
        return _MultiSelect(
          options: [
            for (final b in options) (id: b.id, label: b.name),
          ],
          selected: selected,
          enabled: enabled,
        );
      },
    );
  }
}

class _CenterPicker extends ConsumerWidget {
  const _CenterPicker({
    required this.academyId,
    required this.selected,
    this.enabled = true,
  });
  final String academyId;
  final Set<String> selected;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    return FutureBuilder<List<({String id, String name})>>(
      future: () async {
        final rows = await client
            .from('centers')
            .select('id, name')
            .eq('academy_id', academyId)
            .eq('is_active', true)
            .order('name');
        return [
          for (final r in rows as List)
            (id: (r as Map)['id'] as String, name: r['name'] as String),
        ];
      }(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _PickerLoading();
        }
        final options = snap.data ?? const [];
        if (options.isEmpty) {
          return const _PickerEmpty(message: 'No active centers.');
        }
        return _MultiSelect(
          options: [
            for (final c in options) (id: c.id, label: c.name),
          ],
          selected: selected,
          enabled: enabled,
        );
      },
    );
  }
}

/// Compact loading row for a picker that is still fetching its options.
class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.sm),
          Text('Loading…'),
        ],
      ),
    );
  }
}

/// Muted note shown when a picker has no options to choose from.
class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _MultiSelect extends StatefulWidget {
  const _MultiSelect({
    required this.options,
    required this.selected,
    this.enabled = true,
  });
  final List<({String id, String label})> options;
  final Set<String> selected;
  final bool enabled;

  @override
  State<_MultiSelect> createState() => _MultiSelectState();
}

class _MultiSelectState extends State<_MultiSelect> {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final o in widget.options)
          FilterChip(
            label: Text(o.label),
            selected: widget.selected.contains(o.id),
            onSelected: widget.enabled
                ? (sel) => setState(() {
                      if (sel) {
                        widget.selected.add(o.id);
                      } else {
                        widget.selected.remove(o.id);
                      }
                    })
                : null,
          ),
      ],
    );
  }
}
