import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Self-service profile editor available to every signed-in user.
/// Edits name + phone on the `users` row and uploads an avatar into
/// `avatars/<academy_id>/users/<own_id>/`. Email is read-only here (changing
/// it goes through Supabase Auth, not this page).
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  bool _uploading = false;
  bool _seeded = false;

  void _seed() {
    if (_seeded) return;
    final p = ref.read(currentProfileProvider).valueOrNull;
    if (p == null) return;
    _firstName.text = p.firstName ?? '';
    _lastName.text = p.lastName ?? '';
    _phone.text = p.phone ?? '';
    _seeded = true;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile == null) return;
    setState(() => _saving = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.from('users').update({
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      }).eq('id', profile.id);
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Profile updated.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto() async {
    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile == null || profile.academyId == null) return;
    setState(() => _uploading = true);
    try {
      final storage = ref.read(storageServiceProvider);
      final path = await storage.pickAndUploadOwnAvatar(
        academyId: profile.academyId!,
        userId: profile.id,
      );
      if (path == null) return;
      final client = ref.read(supabaseClientProvider);
      await client
          .from('users')
          .update({'profile_photo': path}).eq('id', profile.id);
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Profile photo updated.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(currentProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: async.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(currentProfileProvider),
        ),
        data: (profile) {
          if (profile == null) {
            return const AppEmptyState(
              icon: Icons.person_off_outlined,
              title: 'Not signed in',
              subtitle: 'Sign in to view and edit your profile.',
            );
          }
          _seed();
          final photoUrl = ref
              .read(storageServiceProvider)
              .publicAvatarUrl(profile.profilePhoto);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _ProfileHeader(
                photoUrl: photoUrl,
                name: profile.displayName,
                role: _roleLabel(profile.role),
                uploading: _uploading,
                onChangePhoto: _changePhoto,
              ),
              const SizedBox(height: AppSpacing.xl),
              const AppSectionHeader(title: 'Your details'),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stack = constraints.maxWidth < AppBreakpoints.phone;
                  final firstField = AppFormField(
                    controller: _firstName,
                    label: 'First name',
                    enabled: !_saving,
                    textInputAction: TextInputAction.next,
                  );
                  final lastField = AppFormField(
                    controller: _lastName,
                    label: 'Last name',
                    enabled: !_saving,
                    textInputAction: TextInputAction.next,
                  );
                  if (stack) {
                    return Column(
                      children: [
                        firstField,
                        const SizedBox(height: AppSpacing.md),
                        lastField,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: firstField),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: lastField),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _phone,
                label: 'Phone',
                enabled: !_saving,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.xl),
              const AppSectionHeader(title: 'Account'),
              const SizedBox(height: AppSpacing.sm),
              _AccountCard(
                email: profile.email,
                role: _roleLabel(profile.role),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Turns a raw `user_role` enum value (e.g. `center_admin`) into a readable
/// label for display (e.g. `Center admin`).
String _roleLabel(String role) {
  if (role.isEmpty) return role;
  final spaced = role.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Compact identity header: avatar alongside name + role, with an inline
/// "Change photo" affordance — replaces the tall centered avatar block.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.photoUrl,
    required this.name,
    required this.role,
    required this.uploading,
    required this.onChangePhoto,
  });

  final String? photoUrl;
  final String name;
  final String role;
  final bool uploading;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          _AvatarPreview(
            url: photoUrl,
            fallback: name.isNotEmpty ? name[0].toUpperCase() : '?',
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  role,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: uploading ? null : onChangePhoto,
                    icon: uploading
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                    label: const Text('Change photo'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only account facts (email + role). Visually distinct from the editable
/// "Your details" fields — rendered as labelled rows inside a card so they read
/// as information, not inputs.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.email, required this.role});

  final String? email;
  final String role;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          _AccountRow(
            icon: Icons.mail_outline,
            label: 'Email',
            value: email ?? '—',
          ),
          const Divider(height: 1),
          _AccountRow(
            icon: Icons.badge_outlined,
            label: 'Role',
            value: role,
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: AppType.semibold,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.url, required this.fallback});
  final String? url;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return CircleAvatar(
        radius: 28,
        child: Text(fallback, style: Theme.of(context).textTheme.titleLarge),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        placeholder: (_, __) => const CircleAvatar(
          radius: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: 28,
          child: Text(fallback, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
    );
  }
}
