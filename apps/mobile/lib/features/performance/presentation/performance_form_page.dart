import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/students/data/student.dart';

/// Coach-facing form: pick sport rubric, score skills, attach media,
/// add qualitative feedback, save.
class PerformanceFormPage extends ConsumerStatefulWidget {
  const PerformanceFormPage({required this.student, this.batchId, super.key});

  final Student student;
  final String? batchId;

  @override
  ConsumerState<PerformanceFormPage> createState() =>
      _PerformanceFormPageState();
}

class _PerformanceFormPageState extends ConsumerState<PerformanceFormPage> {
  late String _sport = widget.student.sport ?? 'general';
  late final List<SkillEntry> _skills = rubricFor(_sport)
      .map((n) => SkillEntry(name: n))
      .toList();
  final _feedback = TextEditingController();
  bool _saving = false;

  /// After we save, this holds the new assessment id so we can attach media.
  String? _savedAssessmentId;
  final List<String> _mediaPaths = [];

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  void _setSport(String s) {
    setState(() {
      _sport = s;
      _skills
        ..clear()
        ..addAll(rubricFor(s).map((n) => SkillEntry(name: n)));
    });
  }

  double _overall() {
    final scored = _skills.where((s) => s.name.trim().isNotEmpty).toList();
    if (scored.isEmpty) return 0;
    final sum = scored.fold<int>(0, (a, b) => a + b.score);
    return double.parse((sum / scored.length).toStringAsFixed(2));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final id = await createAssessment(
        ref,
        studentId: widget.student.id,
        batchId: widget.batchId,
        sport: _sport,
        overallScore: _overall(),
        qualitativeFeedback: _feedback.text.trim(),
        skills: _skills,
      );
      setState(() => _savedAssessmentId = id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assessment saved.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _attachPhoto() async {
    final id = _savedAssessmentId;
    if (id == null) return;
    final storage = ref.read(storageServiceProvider);
    final picked = await storage.pickAndUploadPerformancePhoto(
      academyId: widget.student.academyId,
      assessmentId: id,
    );
    if (picked == null) return;
    await attachMedia(
      ref,
      assessmentId: id,
      studentId: widget.student.id,
      mediaType: 'photo',
      filePath: picked.path,
      originalFilename: picked.originalFilename,
      mimeType: picked.mimeType,
      sizeBytes: picked.sizeBytes,
    );
    if (!mounted) return;
    setState(() => _mediaPaths.add(picked.path));
  }

  Future<void> _attachVideo() async {
    final id = _savedAssessmentId;
    if (id == null) return;
    final storage = ref.read(storageServiceProvider);
    final picked = await storage.pickAndUploadPerformanceVideo(
      academyId: widget.student.academyId,
      assessmentId: id,
    );
    if (picked == null) return;
    await attachMedia(
      ref,
      assessmentId: id,
      studentId: widget.student.id,
      mediaType: 'video',
      filePath: picked.path,
      originalFilename: picked.originalFilename,
      mimeType: picked.mimeType,
      sizeBytes: picked.sizeBytes,
    );
    if (!mounted) return;
    setState(() => _mediaPaths.add(picked.path));
  }

  @override
  Widget build(BuildContext context) {
    final saved = _savedAssessmentId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text('Assess · ${widget.student.fullName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _sport,
            items: defaultSkillRubrics.keys
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s[0].toUpperCase() + s.substring(1)),
                    ))
                .toList(),
            onChanged: saved
                ? null
                : (v) {
                    if (v != null) _setSport(v);
                  },
            decoration: const InputDecoration(
              labelText: 'Sport / rubric',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Skills', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < _skills.length; i++)
            _SkillRow(
              entry: _skills[i],
              onChanged: () => setState(() {}),
              onRemove: saved
                  ? null
                  : () => setState(() => _skills.removeAt(i)),
              readOnly: saved,
            ),
          if (!saved) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add skill'),
              onPressed: () {
                setState(() => _skills.add(SkillEntry(name: '')));
              },
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _feedback,
            enabled: !saved,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Feedback (optional)',
              border: OutlineInputBorder(),
              hintText: 'Strengths, areas to work on, parent-facing notes…',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Average score: ',
                  style: Theme.of(context).textTheme.bodyMedium),
              Text(
                _overall().toStringAsFixed(2),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (saved) ...[
            Text('Evidence', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Add photo'),
                  onPressed: _attachPhoto,
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Add video'),
                  onPressed: _attachVideo,
                ),
              ],
            ),
            if (_mediaPaths.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${_mediaPaths.length} attached',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ] else
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save assessment'),
              onPressed: _saving ? null : _save,
            ),
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.entry,
    required this.onChanged,
    required this.onRemove,
    required this.readOnly,
  });

  final SkillEntry entry;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              enabled: !readOnly,
              controller: TextEditingController(text: entry.name)
                ..selection =
                    TextSelection.collapsed(offset: entry.name.length),
              onChanged: (v) {
                entry.name = v;
                onChanged();
              },
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Slider(
              value: entry.score.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${entry.score}',
              onChanged: readOnly
                  ? null
                  : (v) {
                      entry.score = v.round();
                      onChanged();
                    },
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '${entry.score}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}
