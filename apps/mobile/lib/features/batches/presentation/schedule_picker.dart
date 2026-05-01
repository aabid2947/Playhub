import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Days', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TimeField(
                label: 'Start',
                value: _startTime,
                onTap: () => _pickTime(start: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimeField(
                label: 'End',
                value: _endTime,
                onTap: () => _pickTime(start: false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value ?? 'Tap to pick'),
      ),
    );
  }
}
