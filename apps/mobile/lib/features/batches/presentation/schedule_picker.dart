import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/batches/data/batch.dart';

/// Day-of-week chips + start/end time pickers, emitting a [BatchSchedule].
class SchedulePicker extends StatefulWidget {
  const SchedulePicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final BatchSchedule value;
  final ValueChanged<BatchSchedule> onChanged;

  @override
  State<SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends State<SchedulePicker> {
  static const _allDays = [
    ('mon', 'Mon'),
    ('tue', 'Tue'),
    ('wed', 'Wed'),
    ('thu', 'Thu'),
    ('fri', 'Fri'),
    ('sat', 'Sat'),
    ('sun', 'Sun'),
  ];

  late final Set<String> _selected = widget.value.days.toSet();
  late String? _startTime = widget.value.startTime;
  late String? _endTime = widget.value.endTime;

  void _emit() {
    widget.onChanged(BatchSchedule(
      days: _selected.toList(),
      startTime: _startTime,
      endTime: _endTime,
    ));
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = _parse(start ? _startTime : _endTime) ??
        const TimeOfDay(hour: 16, minute: 0);
    final picked =
        await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (start) {
          _startTime = _format(picked);
        } else {
          _endTime = _format(picked);
        }
      });
      _emit();
    }
  }

  /// True when both times are set and start is not before end (invalid range).
  bool get _endBeforeStart {
    final s = _parse(_startTime);
    final e = _parse(_endTime);
    if (s == null || e == null) return false;
    final startMinutes = s.hour * 60 + s.minute;
    final endMinutes = e.hour * 60 + e.minute;
    return endMinutes <= startMinutes;
  }

  static TimeOfDay? _parse(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Display the stored 24h value via the locale-aware [TimeOfDay.format].
  String? _display(String? raw) {
    final parsed = _parse(raw);
    if (parsed == null) return null;
    return parsed.format(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final semantic = AppSemanticColors.of(context);
    final invalidRange = _endBeforeStart;

    // v1 field sub-label: a small navy-ink caption above each control group,
    // matching the label-above style the form's AppFormFields use.
    Widget subLabel(String text) => Text(
          text,
          style: textTheme.labelSmall?.copyWith(
            fontWeight: AppType.semibold,
            color: scheme.onSurfaceVariant,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        subLabel('Days'),
        const SizedBox(height: AppSpacing.sm),
        // Day chips wrap onto multiple rows on narrow widths. Selected chips
        // fill with the brand orange (the v1 selected-state for choice chips).
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (key, label) in _allDays)
              FilterChip(
                label: Text(label),
                selected: _selected.contains(key),
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _selected.add(key);
                    } else {
                      _selected.remove(key);
                    }
                  });
                  _emit();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        subLabel('Time'),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TimeField(
                label: 'Start',
                value: _display(_startTime),
                hasError: invalidRange,
                onTap: () => _pickTime(start: true),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TimeField(
                label: 'End',
                value: _display(_endTime),
                hasError: invalidRange,
                onTap: () => _pickTime(start: false),
              ),
            ),
          ],
        ),
        if (invalidRange) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: semantic.danger,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'End time must be after the start time.',
                  style: textTheme.bodySmall?.copyWith(color: semantic.danger),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.hasError,
    required this.onTap,
  });

  final String label;
  final String? value;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final isSet = value != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: hasError ? '' : null,
          suffixIcon: const Icon(Icons.access_time, size: 20),
          // Keep the error tint without reserving a second error line under
          // each field — the shared message below the row carries the text.
          // height: 0 collapses the (empty) error line to zero height.
          errorStyle: const TextStyle(height: 0),
        ),
        child: Text(
          value ?? 'Set time',
          style: isSet
              ? textTheme.bodyLarge
              : textTheme.bodyLarge
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
