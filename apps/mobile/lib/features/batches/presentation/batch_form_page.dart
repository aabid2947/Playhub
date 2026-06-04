import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/schedule_picker.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class BatchFormPage extends ConsumerStatefulWidget {
  const BatchFormPage({super.key, this.existing});

  final Batch? existing;

  @override
  ConsumerState<BatchFormPage> createState() => _BatchFormPageState();
}

class _BatchFormPageState extends ConsumerState<BatchFormPage> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _ageGroup = TextEditingController(
    text: widget.existing?.ageGroup ?? '',
  );
  late final _capacity = TextEditingController(
    text: widget.existing?.capacity?.toString() ?? '',
  );

  String? _centerId;
  String? _coachId;
  String? _sportId;
  String? _skillLevel;
  late BatchSchedule _schedule;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _centerId = widget.existing?.centerId;
    _coachId = widget.existing?.coachId;
    _sportId = widget.existing?.sportId;
    _skillLevel = widget.existing?.skillLevel;
    _schedule = widget.existing?.schedule ?? const BatchSchedule();
  }

  @override
  void dispose() {
    _name.dispose();
    _ageGroup.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'sport_id': _sportId,
        'age_group': _ageGroup.text.trim().isEmpty
            ? null
            : _ageGroup.text.trim(),
        'capacity': _capacity.text.trim().isEmpty
            ? null
            : int.tryParse(_capacity.text.trim()),
        'center_id': _centerId,
        'coach_id': _coachId,
        'skill_level': _skillLevel,
        'schedule': _schedule.toMap(),
      };
      if (isEdit) {
        await updateBatch(ref, widget.existing!.id, patch);
      } else {
        await createBatch(ref, patch);
      }
      if (mounted) context.pop();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centresAsync = ref.watch(centersProvider);
    final coachesAsync = ref.watch(coachesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit batch' : 'New batch')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppFormField(
                controller: _name,
                label: 'Batch name *',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SportPicker(
                      value: _sportId,
                      onChanged: (v) => setState(() => _sportId = v),
                      centerId: _centerId,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppFormField(
                      controller: _ageGroup,
                      label: 'Age group',
                      hint: '6-10, U-15',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              centresAsync.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (e, _) => Text(friendlyError(e)),
                data: (centres) => DropdownButtonFormField<String>(
                  initialValue: _centerId,
                  decoration: const InputDecoration(labelText: 'Center'),
                  items: [
                    const DropdownMenuItem<String>(child: Text('— none —')),
                    for (final c in centres.where((c) => c.isActive))
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _centerId = v),
                ),
              ),
              const SizedBox(height: 12),
              coachesAsync.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (e, _) => Text(friendlyError(e)),
                data: (coaches) => DropdownButtonFormField<String>(
                  initialValue: _coachId,
                  decoration: const InputDecoration(labelText: 'Coach'),
                  items: [
                    const DropdownMenuItem<String>(
                      child: Text('— unassigned —'),
                    ),
                    for (final c in coaches)
                      DropdownMenuItem(value: c.id, child: Text(c.fullName)),
                  ],
                  onChanged: (v) => setState(() => _coachId = v),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _skillLevel,
                decoration: const InputDecoration(labelText: 'Skill level'),
                items: const [
                  DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
                  DropdownMenuItem(
                    value: 'intermediate',
                    child: Text('Intermediate'),
                  ),
                  DropdownMenuItem(value: 'advanced', child: Text('Advanced')),
                  DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                ],
                onChanged: (v) => setState(() => _skillLevel = v),
              ),
              const SizedBox(height: AppSpacing.xl),
              const AppSectionHeader(title: 'Schedule'),
              const SizedBox(height: AppSpacing.sm),
              SchedulePicker(value: _schedule, onChanged: (s) => _schedule = s),
              const SizedBox(height: 24),
              AppFormField(
                controller: _capacity,
                label: 'Capacity',
                keyboardType: TextInputType.number,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isEdit ? 'Save changes' : 'Create batch'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
