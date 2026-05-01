import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/attendance/data/attendance.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live attendance feed for admins. Subscribes to inserts/updates on
/// `attendance_records` for the current academy, today only, and surfaces
/// the latest changes as they land.
final _todaysAttendanceStreamProvider =
    StreamProvider.autoDispose<List<AttendanceRecord>>((ref) async* {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    yield const [];
    return;
  }
  final client = ref.read(supabaseClientProvider);
  final today = DateTime.now();
  final ymd = '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';

  // Initial snapshot
  final initial = await client
      .from('attendance_records')
      .select()
      .eq('academy_id', academyId)
      .eq('date', ymd)
      .order('updated_at', ascending: false);
  final state = <String, AttendanceRecord>{
    for (final r in (initial as List))
      (r as Map<String, dynamic>)['id'] as String:
          AttendanceRecord.fromMap(r),
  };
  yield state.values.toList()
    ..sort((a, b) =>
        (b.checkInTime ?? b.date).compareTo(a.checkInTime ?? a.date));

  // Realtime stream — Supabase realtime delivers row payloads on every
  // insert/update; we filter on academy + date client-side.
  final controller = StreamController<List<AttendanceRecord>>();
  final channel = client.channel('attendance-overview-$academyId');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'attendance_records',
        callback: (payload) {
          final raw = payload.newRecord;
          if (raw.isEmpty) return;
          if (raw['academy_id'] != academyId) return;
          if (raw['date'] != ymd) return;
          if (payload.eventType == PostgresChangeEvent.delete) {
            state.remove(raw['id']);
          } else {
            state[raw['id'] as String] =
                AttendanceRecord.fromMap(raw);
          }
          if (!controller.isClosed) {
            controller.add(state.values.toList()
              ..sort((a, b) => (b.checkInTime ?? b.date)
                  .compareTo(a.checkInTime ?? a.date)));
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    controller.close();
    client.removeChannel(channel);
  });

  yield* controller.stream;
});

/// Admin live overview: total marked today, present/absent split, recent
/// activity feed, all updating in real-time as coaches mark attendance.
class AdminAttendanceOverview extends ConsumerWidget {
  const AdminAttendanceOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(_todaysAttendanceStreamProvider);
    final batches = ref.watch(batchesProvider).valueOrNull ?? const <Batch>[];
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Live attendance')),
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (records) {
          final present = records
              .where((r) =>
                  r.status == AttendanceStatus.present ||
                  r.status == AttendanceStatus.late)
              .length;
          final absent = records
              .where((r) => r.status == AttendanceStatus.absent)
              .length;
          final excused = records
              .where((r) => r.status == AttendanceStatus.excused)
              .length;
          final byBatch = <String, int>{};
          for (final r in records) {
            byBatch[r.batchId] = (byBatch[r.batchId] ?? 0) + 1;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryRow(
                total: records.length,
                present: present,
                absent: absent,
                excused: excused,
              ),
              const SizedBox(height: 16),
              Text(
                'Activity',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (records.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No attendance marked yet today.'),
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final r in records.take(40))
                        ListTile(
                          leading: _StatusDot(status: r.status),
                          title: Text(_studentName(r.studentId, students)),
                          subtitle: Text(
                            _batchName(r.batchId, batches),
                          ),
                          trailing: Text(
                            r.status.label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _studentName(String id, List<Student> students) {
    for (final s in students) {
      if (s.id == id) return s.fullName;
    }
    return '(unknown student)';
  }

  String _batchName(String id, List<Batch> batches) {
    for (final b in batches) {
      if (b.id == id) return b.name;
    }
    return '(unknown batch)';
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.total,
    required this.present,
    required this.absent,
    required this.excused,
  });

  final int total;
  final int present;
  final int absent;
  final int excused;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Cell(label: 'Marked', value: '$total')),
        const SizedBox(width: 8),
        Expanded(
          child: _Cell(
            label: 'Present',
            value: '$present',
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Cell(
            label: 'Absent',
            value: '$absent',
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Cell(
            label: 'Excused',
            value: '$excused',
            color: Colors.orange,
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color?.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: color,
                    )),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AttendanceStatus.present => Colors.green,
      AttendanceStatus.late => Colors.amber,
      AttendanceStatus.absent => Colors.red,
      AttendanceStatus.excused => Colors.orange,
    };
    return CircleAvatar(
      radius: 14,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(
        switch (status) {
          AttendanceStatus.present => Icons.check,
          AttendanceStatus.late => Icons.access_time,
          AttendanceStatus.absent => Icons.close,
          AttendanceStatus.excused => Icons.event_busy,
        },
        size: 14,
        color: color,
      ),
    );
  }
}
