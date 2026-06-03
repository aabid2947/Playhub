import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/announcements/data/announcement_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement sent')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = '$e');
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (profile) {
          final academyId = profile?.academyId;
          if (academyId == null) {
            return const Center(child: Text('No academy'));
          }
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _subject,
                  decoration: const InputDecoration(labelText: 'Subject *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _body,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Body *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 24),
                Text('Audience',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                    'Leave all empty to target everyone in the academy.'),
                const SizedBox(height: 12),
                _RoleChips(selected: _selectedRoles),
                const SizedBox(height: 12),
                _BatchPicker(
                    academyId: academyId, selected: _selectedBatches),
                const SizedBox(height: 12),
                _CenterPicker(
                    academyId: academyId, selected: _selectedCenters),
                const Divider(height: 32),
                Text('Channels',
                    style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Push notification (FCM)'),
                  value: _viaPush,
                  onChanged: (v) => setState(() => _viaPush = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In-app feed'),
                  value: _viaInApp,
                  onChanged: (v) => setState(() => _viaInApp = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Email'),
                  value: _viaEmail,
                  onChanged: (v) => setState(() => _viaEmail = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: Text(_busy ? 'Sending…' : 'Send announcement'),
                  onPressed: _busy ? null : _send,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RoleChips extends StatefulWidget {
  const _RoleChips({required this.selected});
  final Set<String> selected;

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
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in _roles)
          FilterChip(
            label: Text(_labels[r] ?? r),
            selected: widget.selected.contains(r),
            onSelected: (sel) => setState(() {
              if (sel) {
                widget.selected.add(r);
              } else {
                widget.selected.remove(r);
              }
            }),
          ),
      ],
    );
  }
}

class _BatchPicker extends ConsumerWidget {
  const _BatchPicker({required this.academyId, required this.selected});
  final String academyId;
  final Set<String> selected;

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
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _MultiSelect(
          label: 'Batches',
          options: [
            for (final b in snap.data!) (id: b.id, label: b.name),
          ],
          selected: selected,
        );
      },
    );
  }
}

class _CenterPicker extends ConsumerWidget {
  const _CenterPicker({required this.academyId, required this.selected});
  final String academyId;
  final Set<String> selected;

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
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _MultiSelect(
          label: 'Centers',
          options: [
            for (final c in snap.data!) (id: c.id, label: c.name),
          ],
          selected: selected,
        );
      },
    );
  }
}

class _MultiSelect extends StatefulWidget {
  const _MultiSelect({
    required this.label,
    required this.options,
    required this.selected,
  });
  final String label;
  final List<({String id, String label})> options;
  final Set<String> selected;

  @override
  State<_MultiSelect> createState() => _MultiSelectState();
}

class _MultiSelectState extends State<_MultiSelect> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in widget.options)
              FilterChip(
                label: Text(o.label),
                selected: widget.selected.contains(o.id),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    widget.selected.add(o.id);
                  } else {
                    widget.selected.remove(o.id);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }
}
