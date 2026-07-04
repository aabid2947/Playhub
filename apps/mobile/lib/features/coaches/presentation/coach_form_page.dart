import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/coaches/presentation/coach_documents_section.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class CoachFormPage extends ConsumerStatefulWidget {
  const CoachFormPage({super.key, this.existing});

  final Coach? existing;

  @override
  ConsumerState<CoachFormPage> createState() => _CoachFormPageState();
}

class _CoachFormPageState extends ConsumerState<CoachFormPage> {
  late final _firstName =
      TextEditingController(text: widget.existing?.firstName ?? '');
  late final _lastName =
      TextEditingController(text: widget.existing?.lastName ?? '');
  late final _email =
      TextEditingController(text: widget.existing?.email ?? '');
  late final _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final _specialization = TextEditingController(
      text: widget.existing?.specialization.join(', ') ?? '');
  late final _qualifications = TextEditingController(
      text: widget.existing?.qualifications.join(', ') ?? '');
  late final _certifications = TextEditingController(
      text: widget.existing?.certifications.join(', ') ?? '');
  late final _experience = TextEditingController(
      text: widget.existing?.experienceYears?.toString() ?? '');
  late final _salary = TextEditingController(
      text: widget.existing?.salary?.toStringAsFixed(0) ?? '');

  String? _centerId;
  String? _paymentType;
  String? _photo;
  final Set<String> _sportIds = <String>{};
  // Existing coaches load their sports asynchronously (see initState). Until
  // that resolves, _sportIds is empty but NOT genuinely sportless — so the
  // save-time "≥1 sport" guard must wait for this, or it false-blocks (and a
  // save in the gap would wipe the coach's sports via setCoachSports([])).
  bool _sportsHydrated = false;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _centerId = widget.existing?.centerId;
    _paymentType = widget.existing?.paymentType;
    _photo = widget.existing?.photo;
    final id = widget.existing?.id;
    // A brand-new coach has nothing to load, so it's "hydrated" immediately.
    _sportsHydrated = id == null;
    if (id != null) {
      // Hydrate the coach's existing sport assignments, if any. Mark hydrated
      // in `finally` so a load error unlocks the form rather than trapping it.
      Future.microtask(() async {
        try {
          final ids = await ref.read(coachSportsProvider(id).future);
          if (mounted) setState(() => _sportIds.addAll(ids));
        } finally {
          if (mounted) setState(() => _sportsHydrated = true);
        }
      });
    }
  }

  String _initials() {
    final f = _firstName.text.trim();
    final l = _lastName.text.trim();
    return '${f.isEmpty ? '' : f[0]}${l.isEmpty ? '' : l[0]}';
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _specialization.dispose();
    _qualifications.dispose();
    _certifications.dispose();
    _experience.dispose();
    _salary.dispose();
    super.dispose();
  }

  String? _emptyToNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // A coach must belong to a center. A null-center coach is visible/editable
    // by every center_admin (center_admin_sees_*(null)=true), breaking per-
    // center isolation. The dropdown validator covers the data state; this
    // backstops loading/error and the no-centers case.
    if (_centerId == null) {
      AppSnackbar.error(
        context,
        'Pick a center for this coach — add one in Settings → Centers first.',
      );
      return;
    }
    // Don't judge sports until the existing coach's assignments have loaded —
    // otherwise a quick save false-blocks (and setCoachSports below would wipe
    // them). New coaches are hydrated immediately, so this only gates edits.
    if (!_sportsHydrated) {
      AppSnackbar.error(
        context,
        "Still loading this coach's details — try again in a moment.",
      );
      return;
    }
    // At least one sport: head_coach sport-scoping and coach->batch assignment
    // key off coach_sports; a sportless coach falls back to center-only scope.
    // The chip multi-select doesn't take part in Form.validate(), so guard here.
    if (_sportIds.isEmpty) {
      AppSnackbar.error(
        context,
        'Select at least one sport — enable sports in Settings → Sports first.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final patch = <String, dynamic>{
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'email': _emptyToNull(_email),
        'phone': _emptyToNull(_phone),
        'specialization': splitCsv(_specialization.text),
        'qualifications': splitCsv(_qualifications.text),
        'certifications': splitCsv(_certifications.text),
        'experience_years': _experience.text.trim().isEmpty
            ? null
            : int.tryParse(_experience.text.trim()),
        'salary': _salary.text.trim().isEmpty
            ? null
            : double.tryParse(_salary.text.trim()),
        'payment_type': _paymentType,
        'center_id': _centerId,
        'photo': _photo,
      };
      final saved = isEdit
          ? await updateCoach(ref, widget.existing!.id, patch)
          : await createCoach(ref, patch);
      final repo = await ref.read(sportsRepoProvider.future);
      if (repo != null) {
        await repo.setCoachSports(saved.id, _sportIds.toList());
        ref.invalidate(coachSportsProvider(saved.id));
      }
      if (!mounted) return;
      AppSnackbar.success(
        context,
        isEdit ? 'Coach updated.' : 'Coach created.',
      );
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Soft-delete: archive the coach (is_active → false). Reversible, and keeps
  /// the record so historical attendance/performance stay attributed.
  Future<void> _confirmArchive() async {
    final ok = await confirmAction(
      context,
      title: 'Archive this coach?',
      message:
          'They will be marked inactive and hidden from coach pickers, and '
          'unassigned from new work. Their record, documents and history are '
          'kept — you can reactivate later.',
      confirmLabel: 'Archive',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await archiveCoach(ref, widget.existing!.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Coach archived.');
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centresAsync = ref.watch(centersProvider);
    final caps = ref.watch(capabilitiesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit coach' : 'New coach')),
      // v1 archetype D: the primary action is pinned to a soft-floating bottom
      // bar so it's always reachable above the long edit-mode form.
      bottomNavigationBar: _SaveBar(
        label: isEdit ? 'Save changes' : 'Create coach',
        busy: _busy,
        onPressed: _busy ? null : _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Center(
              child: AvatarPicker(
                entity: 'coaches',
                url: _photo,
                fallbackInitials: _initials(),
                onUploaded: (url) => setState(() => _photo = url),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // One consistent required-marker legend for the whole form.
            Text(
              'Fields marked * are required.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Personal ──────────────────────────────────────────────
            const AppSectionHeader(title: 'Personal'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _firstName,
                    label: 'First name *',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppFormField(
                    controller: _lastName,
                    label: 'Last name *',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _email,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppFormField(
                    controller: _phone,
                    label: 'Phone',
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Expertise ─────────────────────────────────────────────
            // Sports coached is its own labeled block (a structured
            // multi-select), kept distinct from the free-text sub-specialty
            // and the comma-separated credential fields below it.
            const AppSectionHeader(title: 'Expertise'),
            const SizedBox(height: AppSpacing.sm),
            _SportsField(
              selectedIds: _sportIds,
              onToggle: (sid, sel) => setState(() {
                if (sel) {
                  _sportIds.add(sid);
                } else {
                  _sportIds.remove(sid);
                }
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _specialization,
              label: 'Sub-specialty / notes',
              hint: 'Batting, Wicket-keeping, …',
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _experience,
              label: 'Experience (yrs)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _qualifications,
              label: 'Qualifications',
              hint: 'BPEd, MPEd (comma-separated)',
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _certifications,
              label: 'Certifications',
              hint: 'NIS Level 1, ICC Coaching Certificate',
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Assignment ────────────────────────────────────────────
            const AppSectionHeader(title: 'Assignment'),
            const SizedBox(height: AppSpacing.sm),
            centresAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: AppLoading(),
              ),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(centersProvider),
              ),
              data: (centres) => AppDropdownField<String>(
                label: 'Center *',
                value: _centerId,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
                items: [
                  const DropdownMenuItem<String>(
                    child: Text('— select a center —'),
                  ),
                  for (final c in centres.where((c) => c.isActive))
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name),
                    ),
                ],
                onChanged: (v) => setState(() => _centerId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Compensation ──────────────────────────────────────────
            const AppSectionHeader(title: 'Compensation'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _salary,
                    label: 'Salary (₹)',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppDropdownField<String>(
                    label: 'Payment type',
                    value: _paymentType,
                    items: const [
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text('Monthly'),
                      ),
                      DropdownMenuItem(
                        value: 'hourly',
                        child: Text('Hourly'),
                      ),
                      DropdownMenuItem(
                        value: 'session',
                        child: Text('Per session'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _paymentType = v),
                  ),
                ),
              ],
            ),

            // ── Edit-only sections, clearly separated below a divider ──
            if (isEdit) ...[
              const SizedBox(height: AppSpacing.xxl),
              const Divider(),
              const SizedBox(height: AppSpacing.lg),
              CoachDocumentsSection(coachId: widget.existing!.id),
              const SizedBox(height: AppSpacing.xl),
              const AppSectionHeader(title: 'Login & access'),
              const SizedBox(height: AppSpacing.sm),
              _LoginAccessCard(
                coach: widget.existing!,
                onInvite: () => _invite(context),
              ),
              if (caps.manageCoaches) ...[
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Danger zone'),
                const SizedBox(height: AppSpacing.sm),
                _ArchiveButton(
                  label: 'Archive coach',
                  busy: _busy,
                  onPressed: _confirmArchive,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Opens the invite sheet for the (saved) coach, after checking an email
  /// is on file. Kept on the State so the gated edit-only login card can call
  /// it without duplicating the email-check / preset wiring.
  void _invite(BuildContext context) {
    final coach = widget.existing!;
    final email = (coach.email ?? '').trim();
    if (email.isEmpty) {
      AppSnackbar.info(
        context,
        "Set the coach's email above first, then save before inviting.",
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InviteUserSheet(
        preset: InvitePreset(
          role: 'coach',
          title: 'Invite ${coach.firstName} to log in',
          email: coach.email,
          firstName: coach.firstName,
          lastName: coach.lastName,
          linkCoachId: coach.id,
        ),
      ),
    );
  }
}

/// Pinned bottom action bar for the form (v1 archetype D). A full-width primary
/// [FilledButton] on a white bar lifted with [AppShadows.floating]; the button
/// swaps to an inline spinner while [busy]. Mirrors the student form's save bar.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
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
          child: FilledButton(
            onPressed: onPressed,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ),
      ),
    );
  }
}

/// The "Sports coached" expertise block. Watches the academy-wide sports
/// source directly so the form can show a real loading / error state while
/// the catalog resolves — the [SportMultiSelect] itself only sees resolved
/// data, so it never flashes its "no sports configured" hint during load.
class _SportsField extends ConsumerWidget {
  const _SportsField({required this.selectedIds, required this.onToggle});

  final Set<String> selectedIds;
  final void Function(String sportId, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sportsAsync = ref.watch(academyCenterSportsProvider);
    return sportsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: AppLoading(),
      ),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(academyCenterSportsProvider),
      ),
      data: (_) => SportMultiSelect(
        label: 'Sports coached',
        selectedIds: selectedIds,
        onToggle: onToggle,
      ),
    );
  }
}

/// Edit-only card explaining and acting on the coach's login state.
///
/// Three states, each with its own badge so the situation is unambiguous:
///   • no email on file  → can't invite yet (info badge, disabled)
///   • email, no user_id → invite available (warning "Not invited" badge)
///   • user_id present    → already has a login (success "Active" badge)
class _LoginAccessCard extends StatelessWidget {
  const _LoginAccessCard({required this.coach, required this.onInvite});

  final Coach coach;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final hasLogin = coach.userId != null;
    final hasEmail = (coach.email ?? '').trim().isNotEmpty;

    final (IconData icon, String title, String subtitle, Widget badge) =
        switch ((hasLogin, hasEmail)) {
      (true, _) => (
          Icons.verified_user_outlined,
          'Coach has a login',
          'They can already sign in as a coach.',
          const AppBadge(text: 'Active', tone: AppBadgeTone.success),
        ),
      (false, true) => (
          Icons.lock_open_outlined,
          'Invite this coach to log in',
          'Sends a magic-link to the email above so they can sign in as a '
              'coach.',
          const AppBadge(text: 'Not invited', tone: AppBadgeTone.warning),
        ),
      (false, false) => (
          Icons.mark_email_unread_outlined,
          'Add an email to invite',
          "Set the coach's email above and save first, then you can invite "
              'them to log in.',
          const AppBadge(text: 'No email', tone: AppBadgeTone.info),
        ),
    };

    // Only the "email, no login" state is actionable; the other two have no
    // tap target (already has a login / needs an email first).
    final canInvite = !hasLogin && hasEmail;

    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: badge,
        onTap: canInvite ? onInvite : null,
      ),
    );
  }
}

/// Full-width destructive outlined button for the form "Danger zone". Tinted
/// with the theme danger color and disabled while [busy], matching the
/// lifecycle-action styling used on the center form.
class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final danger = AppSemanticColors.of(context).danger;
    return OutlinedButton.icon(
      icon: Icon(Icons.archive_outlined, color: danger),
      label: Text(label, style: TextStyle(color: danger)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: danger.withValues(alpha: 0.5)),
      ),
      onPressed: busy ? null : onPressed,
    );
  }
}
