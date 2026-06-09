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
    final scheme = theme.colorScheme;
    final saved = _savedAssessmentId != null;
    final overall = _overall();
    return Scaffold(
      appBar: AppBar(
        title: Text('Assess · ${widget.student.fullName}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                // --- Who / running average callout ----------------------
                _OverallCallout(
                  studentName: widget.student.fullName,
                  overall: overall,
                  saved: saved,
                ),
                const SizedBox(height: AppSpacing.xl),

                // --- Rubric ----------------------------------------------
                const AppSectionHeader(
                  title: 'Rubric',
                  icon: Icons.sports_outlined,
                ),
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

                // --- Skills ----------------------------------------------
                AppSectionHeader(
                  title: 'Skills',
                  icon: Icons.tune_rounded,
                  trailing: AppBadge(text: '${_skills.length}'),
                ),
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

                // --- Feedback --------------------------------------------
                const AppSectionHeader(
                  title: 'Feedback',
                  icon: Icons.chat_bubble_outline_rounded,
                ),
                const SizedBox(height: AppSpacing.xs),
                AppFormField(
                  controller: _feedback,
                  enabled: !saved,
                  maxLines: 4,
                  hint: 'Strengths, areas to work on, parent-facing notes…',
                ),

                // --- Post-save evidence ----------------------------------
                if (saved) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const AppSectionHeader(
                    title: 'Evidence',
                    icon: Icons.collections_outlined,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attach photos or video to support this assessment.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
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
                          const SizedBox(height: AppSpacing.md),
                          AppBadge(
                            text: '${_mediaPaths.length} attached',
                            tone: AppBadgeTone.success,
                            icon: Icons.check_circle_outline,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // --- Pinned bottom primary action --------------------------------
          _BottomActionBar(
            child: saved
                ? SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save assessment'),
                      onPressed: _saving ? null : _save,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Headline callout for the form: the student plus the running average score,
/// drawn as a 0..10 meter so the coach watches the number build as they score.
/// Flips its caption to "Saved" once the assessment is persisted.
class _OverallCallout extends StatelessWidget {
  const _OverallCallout({
    required this.studentName,
    required this.overall,
    required this.saved,
  });

  final String studentName;
  final double overall;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          AppAvatar(studentName),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AppLabeledProgress(
              label: saved ? 'Saved · average score' : 'Average score',
              value: overall / 10,
              trailing: '${overall.toStringAsFixed(2)} / 10',
            ),
          ),
        ],
      ),
    );
  }
}

/// A pinned bottom action bar with the v1 floating shadow, sitting flush above
/// the safe-area inset so the primary action is always reachable.
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: AppShadows.floating,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: child,
        ),
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
    final scheme = theme.colorScheme;
    // Accent the slider/score with a deterministic color from the skill name so
    // a multi-skill rubric reads as a colorful spread (matches the detail view).
    final accent =
        entry.name.trim().isEmpty ? scheme.primary : colorFromName(entry.name);
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
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: AppType.semibold,
                  ),
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
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: accent,
                    thumbColor: accent,
                    overlayColor: accent.withValues(alpha: 0.12),
                    inactiveTrackColor: scheme.surfaceContainerHighest,
                  ),
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
              ),
              const SizedBox(width: AppSpacing.sm),
              // Fixed-shape score badge keeps the layout stable across 1–10
              // (no jitter as the value crosses single → double digits).
              Container(
                width: 44,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${entry.score}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: AppType.bold,
                    color: accent,
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
