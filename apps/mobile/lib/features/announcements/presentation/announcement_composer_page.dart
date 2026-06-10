import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/announcements/data/announcement.dart';
import 'package:playhub/features/announcements/data/announcement_providers.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:uuid/uuid.dart';

/// Compose + send an announcement. Open to the whole compose ladder
/// (owner/admin/center_admin/head_coach/coach); the audience pickers are
/// scoped to what the role may target (see [composerAudienceProvider]) and the
/// backend re-validates via can_target_announcement. Empty targets = everyone
/// for admins only; non-admins must name at least one batch/sport/center.
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
  // Generated up front so picked media can be uploaded to this announcement's
  // storage folder before the row is inserted on send.
  final _announcementId = const Uuid().v4();
  final _selectedRoles = <String>{};
  final _selectedBatches = <String>{};
  final _selectedCenters = <String>{};
  final _selectedSports = <String>{};
  final _media = <AnnouncementMedia>[];
  bool _viaPush = true;
  bool _viaEmail = false;
  bool _viaInApp = true;
  bool _busy = false;
  // Guards against launching a second image_picker while one is still open —
  // a concurrent pick throws PlatformException('already_active').
  bool _pickingMedia = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _hasAnyTarget =>
      _selectedRoles.isNotEmpty ||
      _selectedBatches.isNotEmpty ||
      _selectedCenters.isNotEmpty ||
      _selectedSports.isNotEmpty;

  Future<void> _pickMedia({
    required String academyId,
    required bool video,
  }) async {
    if (_pickingMedia || _busy) return;
    setState(() => _pickingMedia = true);
    final storage = ref.read(storageServiceProvider);
    try {
      final doc = video
          ? await storage.pickAndUploadAnnouncementVideo(
              academyId: academyId,
              announcementId: _announcementId,
            )
          : await storage.pickAndUploadAnnouncementPhoto(
              academyId: academyId,
              announcementId: _announcementId,
            );
      if (doc == null || !mounted) return;
      setState(() => _media.add(
            AnnouncementMedia(
              path: doc.path,
              type: video ? 'video' : 'image',
              mime: doc.mimeType,
            ),
          ));
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  Future<void> _removeMedia(AnnouncementMedia m) async {
    await ref.read(storageServiceProvider).deleteAnnouncementMedia(m.path);
    if (!mounted) return;
    setState(() => _media.remove(m));
  }

  Future<void> _send({required bool emailAllowed}) async {
    if (!_form.currentState!.validate()) return;
    final caps = ref.read(capabilitiesProvider);
    final isAdmin = caps.announcementTargetsByRole;
    if (!isAdmin && !_hasAnyTarget) {
      setState(() => _error = 'Pick at least one batch, sport, or center.');
      return;
    }
    final viaEmail = emailAllowed && _viaEmail;
    if (!_viaPush && !_viaInApp && !viaEmail) {
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
        id: _announcementId,
        subject: _subject.text.trim(),
        body: _body.text.trim(),
        targetRoles: _selectedRoles.toList(),
        targetBatches: _selectedBatches.toList(),
        targetCenters: _selectedCenters.toList(),
        targetSports: _selectedSports.toList(),
        media: List.of(_media),
        viaPush: _viaPush,
        viaEmail: viaEmail,
        viaInApp: _viaInApp,
      );
      await repo.sendNow(ann.id);
      ref.invalidate(announcementsListProvider);
      if (mounted) {
        AppSnackbar.success(context, 'Announcement sent');
        Navigator.of(context).pop();
      }
    } on Object catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final caps = ref.watch(capabilitiesProvider);
    final emailAllowed = caps.announcementEmailChannel;
    final isAdmin = caps.announcementTargetsByRole;
    return Scaffold(
      appBar: AppBar(title: const Text('New announcement')),
      // v1 archetype D: the send action is pinned to a soft-floating bottom bar
      // so it stays reachable above the long compose form. Hidden until the
      // profile/academy resolve (nothing to send to otherwise).
      bottomNavigationBar: profileAsync.valueOrNull?.academyId == null
          ? null
          : _SendBar(
              busy: _busy,
              onPressed:
                  _busy ? null : () => _send(emailAllowed: emailAllowed),
            ),
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
          final audienceAsync = ref.watch(composerAudienceProvider);
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
                const AppSectionHeader(
                  title: 'Message',
                  icon: Icons.campaign_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
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
                // 'Photos' (not 'Photos & videos') while video upload is off.
                const AppSectionHeader(
                  title: 'Photos',
                  icon: Icons.photo_library_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                _MediaSection(
                  media: _media,
                  enabled: !_busy && !_pickingMedia,
                  uploading: _pickingMedia,
                  onAddPhoto: () =>
                      _pickMedia(academyId: academyId, video: false),
                  // Video upload temporarily disabled — re-enable by restoring
                  // the Video button in _MediaSection and passing:
                  //   onAddVideo: () => _pickMedia(academyId: academyId, video: true),
                  onRemove: (m) => unawaited(_removeMedia(m)),
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(
                  title: 'Audience',
                  icon: Icons.groups_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                _AudienceHint(isAdmin: isAdmin),
                const SizedBox(height: AppSpacing.md),
                audienceAsync.when(
                  loading: () => const _PickerLoading(),
                  error: (e, _) => Text(friendlyError(e)),
                  data: (audience) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (audience.canTargetRoles) ...[
                        _AudienceGroup(
                          label: 'Roles',
                          icon: Icons.badge_outlined,
                          child: _RoleChips(
                            selected: _selectedRoles,
                            enabled: !_busy,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (audience.centers.isNotEmpty) ...[
                        _AudienceGroup(
                          label: 'Centers',
                          icon: Icons.apartment_outlined,
                          child: _OptionChips(
                            options: audience.centers,
                            selected: _selectedCenters,
                            enabled: !_busy,
                            emptyMessage: 'No centers.',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (audience.canTargetSports) ...[
                        _AudienceGroup(
                          label: 'Sports',
                          icon: Icons.sports_outlined,
                          child: _OptionChips(
                            options: audience.sports,
                            selected: _selectedSports,
                            enabled: !_busy,
                            emptyMessage: 'No sports available.',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _AudienceGroup(
                        label: 'Batches',
                        icon: Icons.grid_view_outlined,
                        child: _OptionChips(
                          options: audience.batches,
                          selected: _selectedBatches,
                          enabled: !_busy,
                          emptyMessage: 'No batches you can post to.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(
                  title: 'Channels',
                  icon: Icons.send_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
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
                        secondary: const Icon(Icons.notifications_outlined),
                        value: _viaPush,
                        onChanged:
                            _busy ? null : (v) => setState(() => _viaPush = v),
                      ),
                      SwitchListTile(
                        title: const Text('In-app feed'),
                        subtitle: const Text('Shows in the announcements feed'),
                        secondary: const Icon(Icons.feed_outlined),
                        value: _viaInApp,
                        onChanged:
                            _busy ? null : (v) => setState(() => _viaInApp = v),
                      ),
                      if (emailAllowed)
                        SwitchListTile(
                          title: const Text('Email'),
                          subtitle:
                              const Text('Sent to recipients with an email'),
                          secondary: const Icon(Icons.mail_outline),
                          value: _viaEmail,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _viaEmail = v),
                        ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ErrorBanner(message: _error!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Pinned bottom action bar for the composer (v1 archetype D). A full-width
/// primary [FilledButton] on a soft-floating surface bar; swaps to an inline
/// spinner while [busy].
class _SendBar extends StatelessWidget {
  const _SendBar({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: AppShadows.floating,
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(busy ? 'Sending…' : 'Send announcement'),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

/// Soft info banner explaining the targeting model. The "empty = everyone"
/// rule only applies to the admin tier; everyone else must name a scope.
class _AudienceHint extends StatelessWidget {
  const _AudienceHint({required this.isAdmin});

  final bool isAdmin;

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
          Icon(Icons.info_outline, size: 20, color: semantics.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isAdmin
                  ? 'Leave everything empty to reach everyone in the academy. '
                      'Picking roles, batches, sports or centers narrows who '
                      'receives this.'
                  : 'Pick the batch, sport, or center to notify. Their students '
                      'and parents will receive it.',
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

/// Photo attachments: an add button + a thumbnail strip with remove, plus an
/// "Uploading…" indicator while a pick is being uploaded.
class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.media,
    required this.enabled,
    required this.uploading,
    required this.onAddPhoto,
    required this.onRemove,
  });

  final List<AnnouncementMedia> media;
  final bool enabled;

  /// A pick is being uploaded — show progress and block re-entry.
  final bool uploading;
  final VoidCallback onAddPhoto;
  final ValueChanged<AnnouncementMedia> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: enabled ? onAddPhoto : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add photo'),
            ),
            // Video upload temporarily disabled. To restore: add an
            // `onAddVideo` field back, pass it from the composer, and re-add:
            //   OutlinedButton.icon(
            //     onPressed: enabled ? onAddVideo : null,
            //     icon: const Icon(Icons.video_call_outlined),
            //     label: const Text('Video'),
            //   ),
          ],
        ),
        if (uploading) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Uploading…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: media.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, i) => _MediaThumb(
                media: media[i],
                onRemove: enabled ? () => onRemove(media[i]) : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MediaThumb extends ConsumerWidget {
  const _MediaThumb({required this.media, this.onRemove});
  final AnnouncementMedia media;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fill = scheme.surfaceContainerHighest;
    Widget inner;
    if (media.isVideo) {
      inner = ColoredBox(
        color: fill,
        child: Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 28,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      inner = FutureBuilder<String>(
        future: ref
            .read(storageServiceProvider)
            .signedAnnouncementMediaUrl(media.path),
        builder: (_, snap) {
          if (snap.data == null) return ColoredBox(color: fill);
          return CachedNetworkImage(
            imageUrl: snap.data!,
            fit: BoxFit.cover,
            placeholder: (_, __) => ColoredBox(color: fill),
            errorWidget: (_, __, ___) => ColoredBox(
              color: fill,
              child: Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        },
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(width: 88, height: 88, child: inner),
        ),
        if (onRemove != null)
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.card,
                ),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A labeled wrapper for one audience selector — a small icon · label header
/// over its chip group.
class _AudienceGroup extends StatelessWidget {
  const _AudienceGroup({
    required this.label,
    required this.icon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: AppType.semibold,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

/// Inline validation/error region (matches form error styling).
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

/// Compact loading row for the audience options while they fetch.
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

/// Multi-select filter chips over a fixed option list, with an empty note.
class _OptionChips extends StatefulWidget {
  const _OptionChips({
    required this.options,
    required this.selected,
    required this.emptyMessage,
    this.enabled = true,
  });
  final List<AudienceOption> options;
  final Set<String> selected;
  final String emptyMessage;
  final bool enabled;

  @override
  State<_OptionChips> createState() => _OptionChipsState();
}

class _OptionChipsState extends State<_OptionChips> {
  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) {
      final theme = Theme.of(context);
      return Text(
        widget.emptyMessage,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
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
