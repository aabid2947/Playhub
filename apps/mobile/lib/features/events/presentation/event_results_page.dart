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
class EventResultsPage extends ConsumerWidget {
  const EventResultsPage({required this.eventId, super.key});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regsAsync = ref.watch(eventRegistrationsProvider(eventId));
    final resultsAsync = ref.watch(eventResultsProvider(eventId));
    final students = ref.watch(studentsProvider).valueOrNull ?? const <Student>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results & certificates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref
              ..invalidate(eventRegistrationsProvider(eventId))
              ..invalidate(eventResultsProvider(eventId)),
          ),
        ],
      ),
      body: regsAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref
            ..invalidate(eventRegistrationsProvider(eventId))
            ..invalidate(eventResultsProvider(eventId)),
        ),
        data: (regs) {
          if (regs.isEmpty) {
            return const AppEmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No participants yet',
              subtitle: 'Register students for this event to record results.',
            );
          }
          final results = resultsAsync.valueOrNull ?? const <EventResult>[];
          final byStudent = <String, EventResult>{
            for (final r in results) r.studentId: r,
          };
          return RefreshIndicator(
            onRefresh: () async => ref
              ..invalidate(eventRegistrationsProvider(eventId))
              ..invalidate(eventResultsProvider(eventId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: regs.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) {
                final r = regs[i];
                final s =
                    students.where((s) => s.id == r.studentId).firstOrNull;
                final result = byStudent[r.studentId];
                return _ResultCard(
                  eventId: eventId,
                  regId: r.id,
                  studentId: r.studentId,
                  studentName: s?.fullName ?? r.studentId.substring(0, 8),
                  existing: result,
                );
              },
            ),
          );
        },
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
    final saved = widget.existing != null;
    final issued = widget.existing?.certificateIssuedAt != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity row: tinted avatar → name → result/certificate status.
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.person_outline,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.studentName,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
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
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Place + Score side-by-side; they wrap to stack on narrow widths.
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
            onPressed: (_busy || !saved) ? null : _generateCertificate,
            icon: Icon(issued ? Icons.download_outlined : Icons.verified_outlined),
            label: Text(issued ? 'Re-download certificate' : 'Generate certificate'),
          ),
          if (!saved) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Save the result to enable certificate generation.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
