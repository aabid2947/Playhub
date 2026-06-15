import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes;

/// Self-service profile editor available to every signed-in user — v1
/// "Sports-Light". Edits name + phone on the `users` row and uploads an avatar
/// into `avatars/<academy_id>/users/<own_id>/`. Email is read-only here
/// (changing it goes through Supabase Auth, not this page).
///
/// Pushed page rendered with a navy hero instead of an app bar: a compact
/// identity band (avatar + name + role chip + a hero back button), an editable
/// "Your details" section, and a read-only "Account" section.
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

  /// Lets a signed-in user set a new password in-app (the forgot-password flow
  /// is for signed-OUT users). Supabase's updateUser changes the password for
  /// the current session without needing the old one.
  Future<void> _changePassword() async {
    final newPw = TextEditingController();
    final confirmPw = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFormField(
                controller: newPw,
                label: 'New password',
                obscureText: true,
                validator: (v) => (v == null || v.length < 8)
                    ? 'At least 8 characters'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: confirmPw,
                label: 'Confirm password',
                obscureText: true,
                validator: (v) =>
                    v != newPw.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (ok != true) {
      newPw.dispose();
      confirmPw.dispose();
      return;
    }
    try {
      final client = ref.read(supabaseClientProvider);
      await client.auth.updateUser(UserAttributes(password: newPw.text));
      if (mounted) AppSnackbar.success(context, 'Password updated.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      newPw.dispose();
      confirmPw.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(currentProfileProvider);
    return Scaffold(
      body: async.when(
        loading: () => const AppLoading(),
        error: (e, _) => SafeArea(
          child: AppErrorView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(currentProfileProvider),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return const SafeArea(
              child: AppEmptyState(
                icon: Icons.person_off_outlined,
                title: 'Not signed in',
                subtitle: 'Sign in to view and edit your profile.',
              ),
            );
          }
          _seed();
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // Navy identity hero — avatar + name + role chip, with a hero
              // back button and an inline "Change photo" affordance.
              AppGradientHeader(
                colors: AppPalette.navyGradient,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppCircleIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        _AvatarWithEdit(
                          uploading: _uploading,
                          onChangePhoto: _changePhoto,
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: AppType.heavy,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              AppGlassChip(
                                _roleLabel(profile.role),
                                icon: Icons.badge_outlined,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Body overlaps the hero band upward, v1-style.
              Transform.translate(
                offset: const Offset(0, -AppSpacing.lg),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionHeader(
                        title: 'Your details',
                        icon: Icons.edit_outlined,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stack = constraints.maxWidth <
                                    AppBreakpoints.phone;
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const AppSectionHeader(
                        title: 'Account',
                        icon: Icons.lock_outline_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _AccountCard(
                        email: profile.email,
                        role: _roleLabel(profile.role),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _changePassword,
                          icon: const Icon(Icons.lock_reset_outlined),
                          label: const Text('Change password'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Save'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
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

/// The signed-in user's avatar on the navy hero, with a small circular camera
/// button overlaid bottom-right that triggers the upload (spinner while busy).
class _AvatarWithEdit extends StatelessWidget {
  const _AvatarWithEdit({required this.uploading, required this.onChangePhoto});

  final bool uploading;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        children: [
          const AppUserAvatar(size: 72, onGradient: true),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: scheme.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: uploading ? null : onChangePhoto,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: uploading
                      ? const SizedBox(
                          height: 13,
                          width: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.photo_camera_outlined,
                          size: 14,
                          color: Colors.white,
                        ),
                ),
              ),
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
