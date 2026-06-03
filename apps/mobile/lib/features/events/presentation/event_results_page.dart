import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:playhub/core/error_messages.dart';

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
            onPressed: () {
              ref.invalidate(eventRegistrationsProvider(eventId));
              ref.invalidate(eventResultsProvider(eventId));
            },
          ),
        ],
      ),
      body: regsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (regs) {
          if (regs.isEmpty) {
            return const Center(child: Text('No participants yet'));
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateCertificate() async {
    if (widget.existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the result first')),
      );
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.studentName,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _placement,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Place'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _score,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Score'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
              const SizedBox(width: 12),
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
