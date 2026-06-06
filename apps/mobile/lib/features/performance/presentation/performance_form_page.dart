import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
  String? _sportId;
  final List<SkillEntry> _skills = [];
  final _feedback = TextEditingController();
  bool _saving = false;

  /// After we save, this holds the new assessment id so we can attach media.
  String? _savedAssessmentId;
  final List<String> _mediaPaths = [];

  @override
  void initState() {
    super.initState();
    _sportId = widget.student.sportId;
    if (_sportId != null) {
      _hydrateSkills(_sportId!);
    } else {
      // Fall back to a generic rubric until a sport is picked.
      _skills.addAll(
        genericRubric.map((n) => SkillEntry(name: n)),
      );
    }
  }

  Future<void> _hydrateSkills(String sportId) async {
    final list = await ref.read(sportSkillsProvider(sportId).future);
    if (!mounted) return;
    setState(() {
      _skills
        ..clear()
        ..addAll(list.map((s) => SkillEntry(name: s.name)));
      if (_skills.isEmpty) {
        _skills.addAll(
          genericRubric.map((n) => SkillEntry(name: n)),
        );
      }
    });
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  void _setSport(String? sportId) {
    setState(() => _sportId = sportId);
    if (sportId != null) {
      _hydrateSkills(sportId);
    }
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
        sportId: _sportId,
        overallScore: _overall(),
        qualitativeFeedback: _feedback.text.trim(),
        skills: _skills,
      );
      setState(() => _savedAssessmentId = id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Assessment saved.');
    } on Object catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
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
    final theme = Theme.of(context);
    final saved = _savedAssessmentId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text('Assess · ${widget.student.fullName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // --- Rubric ---------------------------------------------------
          const AppSectionHeader(title: 'Rubric'),
          AbsorbPointer(
            absorbing: saved,
            child: SportPicker(
              value: _sportId,
              onChanged: _setSport,
              label: 'Sport / rubric',
              centerId: widget.student.centerId,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // --- Skills ---------------------------------------------------
          const AppSectionHeader(title: 'Skills'),
          const SizedBox(height: AppSpacing.xs),
          for (var i = 0; i < _skills.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _SkillRow(
                entry: _skills[i],
                onChanged: () => setState(() {}),
                onRemove: saved
                    ? null
                    : () => setState(() => _skills.removeAt(i)),
                readOnly: saved,
              ),
            ),
          if (!saved)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add skill'),
                onPressed: () {
                  setState(() => _skills.add(SkillEntry(name: '')));
                },
              ),
            ),
          const SizedBox(height: AppSpacing.xl),

          // --- Feedback -------------------------------------------------
          const AppSectionHeader(title: 'Feedback'),
          const SizedBox(height: AppSpacing.xs),
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
          const SizedBox(height: AppSpacing.lg),

          // --- Average score callout -----------------------------------
          AppCard(
            child: Row(
              children: [
                Icon(
                  Icons.insights_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Average score',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  _overall().toStringAsFixed(2),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // --- Primary action / post-save evidence ---------------------
          if (saved) ...[
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            const AppSectionHeader(title: 'Evidence'),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Attach photos or video to support this assessment.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
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
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: AppSemanticColors.of(context).success,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${_mediaPaths.length} attached',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
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
            ),
        ],
      ),
    );
  }
}

/// A single scored skill. The name spans the full width on its own line, and
/// the slider + score + remove sit on a second line so nothing crushes on a
/// narrow screen. The score badge keeps a fixed width so it doesn't jitter as
/// the value crosses single → double digits.
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
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
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
                    border: InputBorder.none,
                    hintText: 'Skill name',
                  ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove skill',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
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
              const SizedBox(width: AppSpacing.sm),
              // Fixed-width box keeps the layout stable across 1–10.
              SizedBox(
                width: 36,
                child: Text(
                  '${entry.score}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
