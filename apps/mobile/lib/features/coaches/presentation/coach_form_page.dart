import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/coaches/presentation/coach_documents_section.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/features/subscription/data/trial_limits.dart';
import 'package:playhub/features/subscription/presentation/upgrade_prompt.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class CoachFormPage extends ConsumerStatefulWidget {
  const CoachFormPage({super.key, this.existing, this.kind = 'coach'});

  final Coach? existing;

  /// 'coach' or 'trainer' — the staff kind to CREATE (ignored in edit, which
  /// keeps the existing record's kind). Drives the labels, the saved
  /// coaches.kind, and the role of the login minted from "Login & access"
  /// (a trainer record mints a role=trainer login).
  final String kind;

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

  /// Effective staff kind: the existing record's (edit) else the requested one.
  String get _kind => widget.existing?.kind ?? widget.kind;
  String get _label => _kind == 'trainer' ? 'trainer' : 'coach';
  String get _labelCap => _kind == 'trainer' ? 'Trainer' : 'Coach';

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
    } else {
      // New coach: a center-scoped role (center_admin / head_coach) manages a
      // fixed set of centers, so pre-select their primary center instead of
      // making them choose — the dropdown is also restricted to their centers
      // in build(). Owner / academy_admin pick from every center (no default).
      Future.microtask(() async {
        final profile = await ref.read(currentProfileProvider.future);
        if (!mounted || profile == null) return;
        final scoped =
            profile.role == 'center_admin' || profile.role == 'head_coach';
        if (scoped && profile.centerId != null) {
          setState(() => _centerId = profile.centerId);
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
    // Free-trial coach cap (TrialLimits.maxCoachRecords = 2, which INCLUDES a
    // head_coach's own auto-minted coach record). On CREATE, surface the shared
    // upgrade prompt instead of letting the insert hit the RLS
    // `trial_quota_coaches_insert` policy and bubble up as a raw error — the FAB
    // on the list already gates this, but the form can be reached before
    // trialLimitsProvider resolves or via direct navigation. RLS stays the hard
    // gate; editing an existing coach at the cap is unaffected (INSERT-only).
    if (!isEdit) {
      final limits = await ref.read(trialLimitsProvider.future);
      if (!mounted) return;
      if (limits.coachesReached) {
        await showUpgradePrompt(context, message: limits.coachesMessage);
        return;
      }
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
        // Discriminates the Coaches vs Trainers section. Only meaningful on
        // create; on edit it re-sends the existing kind (a harmless no-op).
        'kind': _kind,
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
        isEdit ? '$_labelCap updated.' : '$_labelCap created.',
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
      title: 'Archive this $_label?',
      message:
          'They will be marked inactive and hidden from pickers, and '
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
      AppSnackbar.success(context, '$_labelCap archived.');
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
    // A center-scoped role (center_admin / head_coach) assigns only into their
    // OWN center(s) — RLS 42501s the rest — so the center picker is restricted
    // to them (and their primary is auto-selected in initState). Owner and
    // academy_admin pick from every center.
    final role = ref.watch(currentProfileProvider).valueOrNull?.role;
    final centerScoped = role == 'center_admin' || role == 'head_coach';
    final myCenters =
        centerScoped ? ref.watch(myCenterIdsProvider).valueOrNull : null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit $_label' : 'New $_label')),
      // v1 archetype D: the primary action is pinned to a soft-floating bottom
      // bar so it's always reachable above the long edit-mode form.
      bottomNavigationBar: _SaveBar(
        label: isEdit ? 'Save changes' : 'Create $_label',
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

            // ── Assignment (center FIRST) ─────────────────────────────
            // The Sports block below is scoped to the chosen center (sports are
            // per-center), so the center must be picked before sports appear.
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
              data: (centres) {
                var active = centres.where((c) => c.isActive).toList();
                // Center-scoped roles may only assign into their own center(s)
                // (RLS 42501s the rest); restrict the options to them. Owner /
                // academy_admin keep the full list.
                if (centerScoped && myCenters != null) {
                  active =
                      active.where((c) => myCenters.contains(c.id)).toList();
                }
                // Guard a stored center that's absent from the options (now
                // inactive, or outside a center-scoped role's centers): the
                // dropdown asserts on a value not among its items. Fall back to
                // "— select —"; the validator then flags it.
                final safeValue =
                    active.any((c) => c.id == _centerId) ? _centerId : null;
                return AppDropdownField<String>(
                  label: 'Center *',
                  value: safeValue,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                  items: [
                    const DropdownMenuItem<String>(
                      child: Text('— select a center —'),
                    ),
                    for (final c in active)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _centerId = v;
                    // Sports are per-center — clear the selection so a stale
                    // sport can't carry into a center that doesn't offer it.
                    _sportIds.clear();
                  }),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Expertise ─────────────────────────────────────────────
            // Sports coached is its own labeled block, scoped to the center
            // chosen above (and to a head_coach's own sports); kept distinct
            // from the free-text sub-specialty + credential fields below.
            const AppSectionHeader(title: 'Expertise'),
            const SizedBox(height: AppSpacing.sm),
            _SportsField(
              centerId: _centerId,
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
                kindLabel: _label,
                onInvite: () => _invite(context),
              ),
              if (caps.manageCoaches) ...[
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(title: 'Danger zone'),
                const SizedBox(height: AppSpacing.sm),
                _ArchiveButton(
                  label: 'Archive $_label',
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
        "Set the $_label's email above first, then save before inviting.",
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InviteUserSheet(
        preset: InvitePreset(
          // A trainer record mints a role=trainer login; a coach record a
          // role=coach one. Both link the login to this coaches row.
          role: _kind == 'trainer' ? 'trainer' : 'coach',
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

/// The "Sports coached" expertise block, scoped to the center chosen above
/// (sports are per-center — a coach can only be qualified for sports the
/// center actually offers). Until a center is picked it shows a hint rather
/// than every academy sport. For a head_coach it is further narrowed to the
/// sports THEY are assigned to — they may only qualify a coach for their own
/// sports. [SportMultiSelect] handles the center-scoped source + empty state.
class _SportsField extends ConsumerWidget {
  const _SportsField({
    required this.centerId,
    required this.selectedIds,
    required this.onToggle,
  });

  final String? centerId;
  final Set<String> selectedIds;
  final void Function(String sportId, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cid = centerId;
    if (cid == null) {
      // Nothing meaningful to show until a center is chosen — guide the user
      // there instead of listing every sport in the academy.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sports coached', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Pick a center first — sports are chosen per center.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    // A head_coach may only qualify a coach for a sport they own themselves
    // (their coach_sports); other roles see the full center list.
    final role = ref.watch(currentProfileProvider).valueOrNull?.role;
    final Set<String>? restrict = role == 'head_coach'
        ? (ref.watch(mySportIdsProvider).valueOrNull ?? const <String>[]).toSet()
        : null;
    // Watch the center's sports here for a real loading / error state; the
    // SportMultiSelect below re-reads the now-cached provider to render chips.
    return ref.watch(centerSportsProvider(cid)).when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: AppLoading(),
      ),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(centerSportsProvider(cid)),
      ),
      data: (_) => SportMultiSelect(
        label: 'Sports coached',
        centerId: cid,
        restrictToSportIds: restrict,
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
  const _LoginAccessCard({
    required this.coach,
    required this.kindLabel,
    required this.onInvite,
  });

  final Coach coach;
  final String kindLabel;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final hasLogin = coach.userId != null;
    final hasEmail = (coach.email ?? '').trim().isNotEmpty;
    final cap = kindLabel.isEmpty
        ? kindLabel
        : '${kindLabel[0].toUpperCase()}${kindLabel.substring(1)}';

    final (IconData icon, String title, String subtitle, Widget badge) =
        switch ((hasLogin, hasEmail)) {
      (true, _) => (
          Icons.verified_user_outlined,
          '$cap has a login',
          'They can already sign in as a $kindLabel.',
          const AppBadge(text: 'Active', tone: AppBadgeTone.success),
        ),
      (false, true) => (
          Icons.lock_open_outlined,
          'Invite this $kindLabel to log in',
          'Sends a magic-link to the email above so they can sign in as a '
              '$kindLabel.',
          const AppBadge(text: 'Not invited', tone: AppBadgeTone.warning),
        ),
      (false, false) => (
          Icons.mark_email_unread_outlined,
          'Add an email to invite',
          "Set the $kindLabel's email above and save first, then you can "
              'invite them to log in.',
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
