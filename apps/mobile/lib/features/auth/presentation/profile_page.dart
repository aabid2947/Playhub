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
              Center(
                child: Column(
                  children: [
                    _AvatarPreview(
                      url: photoUrl,
                      fallback: (profile.firstName?.isNotEmpty ?? false)
                          ? profile.firstName![0]
                          : '?',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: _uploading ? null : _changePhoto,
                      icon: _uploading
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                      label: const Text('Change photo'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const AppSectionHeader(title: 'Your details'),
              const SizedBox(height: AppSpacing.sm),
              AppFormField(
                controller: _firstName,
                label: 'First name',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _lastName,
                label: 'Last name',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _phone,
                label: 'Phone',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.xl),
              const AppSectionHeader(title: 'Account'),
              const SizedBox(height: AppSpacing.sm),
              AppFormField(
                label: 'Email',
                initialValue: profile.email ?? '—',
                enabled: false,
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                label: 'Role',
                initialValue: profile.role,
                enabled: false,
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

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.url, required this.fallback});
  final String? url;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return CircleAvatar(
        radius: 48,
        child: Text(fallback,
            style: Theme.of(context).textTheme.headlineMedium),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        placeholder: (_, __) => const CircleAvatar(
          radius: 48,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: 48,
          child: Text(fallback,
              style: Theme.of(context).textTheme.headlineMedium),
        ),
      ),
    );
  }
}
