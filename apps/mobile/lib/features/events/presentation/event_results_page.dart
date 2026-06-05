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
          return ListView.separated(
            itemCount: regs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = regs[i];
              final s = students.where((s) => s.id == r.studentId).firstOrNull;
              final result = byStudent[r.studentId];
              return _ResultRow(
                eventId: eventId,
                regId: r.id,
                studentId: r.studentId,
                studentName: s?.fullName ?? r.studentId.substring(0, 8),
                existing: result,
              );
            },
          );
        },
      ),
    );
  }
}

class _ResultRow extends ConsumerStatefulWidget {
  const _ResultRow({
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
  ConsumerState<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends ConsumerState<_ResultRow> {
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.studentName,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                child: AppFormField(
                  controller: _placement,
                  label: 'Place',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 100,
                child: AppFormField(
                  controller: _score,
                  label: 'Score',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppFormField(
                  controller: _category,
                  label: 'Category',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
              const SizedBox(width: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _busy ? null : _generateCertificate,
                icon: const Icon(Icons.verified_outlined),
                label: Text(
                  widget.existing?.certificateIssuedAt == null
                      ? 'Generate certificate'
                      : 'Re-download',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
