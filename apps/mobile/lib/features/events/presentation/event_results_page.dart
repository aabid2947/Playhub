import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Per-event results entry — staff records placement / score per registered
/// student and triggers certificate generation.
///
/// v1 "Sports-Light", archetype G (results/ranking): a navy gradient hero
/// carries the event name + "Results" with a summary strip (participants ·
/// results recorded), then a ranked column of [AppCard] result rows — each with
/// a position medal, the participant's [AppAvatar], a status [AppBadge], and an
/// expandable inline editor for placement / score / category + certificate.
/// The record/edit path and its RLS gate are unchanged (this page is reached
/// only by manage-tier roles from the event detail hero; RLS is the real gate).
class EventResultsPage extends ConsumerWidget {
  const EventResultsPage({required this.eventId, super.key});
  final String eventId;

  void _refresh(WidgetRef ref) => ref
    ..invalidate(eventRegistrationsProvider(eventId))
    ..invalidate(eventResultsProvider(eventId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regsAsync = ref.watch(eventRegistrationsProvider(eventId));
    final resultsAsync = ref.watch(eventResultsProvider(eventId));
    final event = ref.watch(eventByIdProvider(eventId)).valueOrNull;
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];

    return Scaffold(
      body: regsAsync.when(
        loading: () => const SafeArea(child: AppLoading()),
        error: (e, _) => SafeArea(
          child: AppErrorView(
            message: friendlyError(e),
            onRetry: () => _refresh(ref),
          ),
        ),
        data: (regs) {
          final results = resultsAsync.valueOrNull ?? const <EventResult>[];
          final byStudent = <String, EventResult>{
            for (final r in results) r.studentId: r,
          };
          // Rank registrations: those with a recorded placement first (ascending
          // placement), then everyone else by name, so the list reads as a
          // leaderboard with the unranked entries trailing it.
          String nameFor(EventRegistration r) =>
              students.where((s) => s.id == r.studentId).firstOrNull?.fullName ??
              r.studentId.substring(0, 8);
          final ordered = [...regs]..sort((a, b) {
              final pa = byStudent[a.studentId]?.placement;
              final pb = byStudent[b.studentId]?.placement;
              if (pa != null && pb != null) return pa.compareTo(pb);
              if (pa != null) return -1;
              if (pb != null) return 1;
              return nameFor(a)
                  .toLowerCase()
                  .compareTo(nameFor(b).toLowerCase());
            });
          final recorded =
              regs.where((r) => byStudent[r.studentId] != null).length;

          return RefreshIndicator(
            onRefresh: () async => _refresh(ref),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Hero(
                  title: event?.title ?? 'Results',
                  participants: regs.length,
                  recorded: recorded,
                  onBack: () => Navigator.of(context).pop(),
                ),
                // Body overlaps the hero band upward, v1-style.
                Transform.translate(
                  offset: const Offset(0, -AppSpacing.xl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: regs.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.emoji_events_outlined,
                            title: 'No participants yet',
                            subtitle: 'Register students for this event to '
                                'record results.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const AppSectionHeader(
                                title: 'Leaderboard',
                                icon: Icons.leaderboard_outlined,
                              ),
                              for (var i = 0; i < ordered.length; i++) ...[
                                if (i > 0)
                                  const SizedBox(height: AppSpacing.md),
                                _ResultCard(
                                  eventId: eventId,
                                  regId: ordered[i].id,
                                  studentId: ordered[i].studentId,
                                  studentName: nameFor(ordered[i]),
                                  existing: byStudent[ordered[i].studentId],
                                ),
                              ],
                              const SizedBox(height: AppSpacing.xl),
                            ],
                          ),
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

/// Archetype-G navy hero: the event title with a "Results & certificates"
/// eyebrow, a hero stat strip (participants · results recorded), and a back
/// circle button to keep the pushed page navigable.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.title,
    required this.participants,
    required this.recorded,
    required this.onBack,
  });

  final String title;
  final int participants;
  final int recorded;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppGradientHeader(
      colors: AppPalette.navyGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: onBack,
              ),
              const Spacer(),
              const AppGlassChip(
                'Results & certificates',
                icon: Icons.emoji_events_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppHeroStatRow(
            stats: [
              ('$participants', 'Participants'),
              ('$recorded', 'Results recorded'),
            ],
          ),
        ],
      ),
    );
  }
}

/// A medal-style position indicator: a tinted disc with the placement number
/// for ranked entries (gold/silver/bronze for the podium), or a muted dash
/// glyph when no placement has been recorded yet.
class _PositionMedal extends StatelessWidget {
  const _PositionMedal({required this.placement});
  final int? placement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = placement;
    // Podium tints from the shared category swatch; brand for the rest.
    final Color tint;
    if (p == null) {
      tint = scheme.onSurfaceVariant;
    } else if (p == 1) {
      tint = AppPalette.categorySwatch[3]; // gold-ish
    } else if (p == 2) {
      tint = AppPalette.categorySwatch[5]; // silver-ish
    } else if (p == 3) {
      tint = AppPalette.categorySwatch[1]; // bronze-ish
    } else {
      tint = AppPalette.brandPrimary;
    }
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: p == null
          ? Icon(Icons.remove_rounded, color: tint, size: 20)
          : Text(
              '$p',
              style: TextStyle(color: tint, fontWeight: AppType.heavy),
            ),
    );
  }
}

class _ResultCard extends ConsumerStatefulWidget {
  const _ResultCard({
    required this.eventId,
    required this.regId,
    required this.studentId,
    required this.studentName,
    this.existing,
  });
  final String eventId;
  final String regId;
  final String studentId;
  final String studentName;
  final EventResult? existing;

  @override
  ConsumerState<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends ConsumerState<_ResultCard> {
  late final TextEditingController _placement;
  late final TextEditingController _score;
  late final TextEditingController _category;
  bool _busy = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _placement = TextEditingController(
      text: widget.existing?.placement?.toString() ?? '',
    );
    _score = TextEditingController(
      text: widget.existing?.score?.toString() ?? '',
    );
    _category = TextEditingController(text: widget.existing?.category ?? '');
    // Open the editor straight away for entries with nothing recorded yet, so
    // staff can fill the leaderboard top-down without an extra tap per row.
    _expanded = widget.existing == null;
  }

  @override
  void dispose() {
    _placement.dispose();
    _score.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final repo = await ref.read(eventsRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.recordResult(
        eventId: widget.eventId,
        studentId: widget.studentId,
        registrationId: widget.regId,
        placement: int.tryParse(_placement.text.trim()),
        score: double.tryParse(_score.text.trim()),
        category:
            _category.text.trim().isEmpty ? null : _category.text.trim(),
      );
      ref.invalidate(eventResultsProvider(widget.eventId));
      if (mounted) AppSnackbar.success(context, 'Result saved.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateCertificate() async {
    if (widget.existing == null) {
      AppSnackbar.info(context, 'Save the result first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(eventsRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      final url = await repo.generateCertificate(widget.existing!.id);
      ref.invalidate(eventResultsProvider(widget.eventId));
      if (!mounted) return;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final existing = widget.existing;
    final saved = existing != null;
    final issued = existing?.certificateIssuedAt != null;

    // A compact summary of the recorded score, shown when collapsed.
    final scoreParts = <String>[
      if (existing?.score != null) '${existing!.score}',
      if (existing?.category != null && existing!.category!.isNotEmpty)
        existing.category!,
    ];

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ranked identity row — tap to toggle the inline editor.
          AppListTile(
            wrapLeading: false,
            onTap: () => setState(() => _expanded = !_expanded),
            leading: _PositionMedal(placement: existing?.placement),
            title: Row(
              children: [
                AppAvatar(widget.studentName, size: 28),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.studentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppBadge(
                    text: issued
                        ? 'Certificate issued'
                        : saved
                            ? 'Result saved'
                            : 'Not recorded',
                    tone: issued
                        ? AppBadgeTone.success
                        : saved
                            ? AppBadgeTone.info
                            : AppBadgeTone.neutral,
                  ),
                  if (scoreParts.isNotEmpty)
                    Text(
                      scoreParts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                ],
              ),
            ),
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              color: muted,
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Place + Score side-by-side.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppFormField(
                          controller: _placement,
                          label: 'Placement',
                          hint: 'e.g. 1',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AppFormField(
                          controller: _score,
                          label: 'Score',
                          hint: 'e.g. 9.5',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _category,
                    label: 'Category',
                    hint: 'e.g. Under-14',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Step 1 — save the result. Step 2 — generate the certificate
                  // (only available once a result exists).
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save result'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed:
                        (_busy || !saved) ? null : _generateCertificate,
                    icon: Icon(
                      issued ? Icons.download_outlined : Icons.verified_outlined,
                    ),
                    label: Text(
                      issued
                          ? 'Re-download certificate'
                          : 'Generate certificate',
                    ),
                  ),
                  if (!saved) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Save the result to enable certificate generation.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
