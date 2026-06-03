import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/audit/data/audit_log.dart';
import 'package:playhub/features/audit/data/audit_log_providers.dart';
import 'package:playhub/core/error_messages.dart';

class AuditLogPage extends ConsumerWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auditLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(auditLogsProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No activity recorded yet.'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(auditLogsProvider),
            child: ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _LogTile(log: logs[i]),
            ),
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
  final AuditLog log;

  IconData get _icon => switch (log.action) {
        'insert' => Icons.add_circle_outline,
        'update' => Icons.edit_outlined,
        'delete' => Icons.delete_outline,
        _ => Icons.info_outline,
      };

  Color _color(BuildContext c) => switch (log.action) {
        'insert' => Colors.green.shade700,
        'update' => Colors.blue.shade700,
        'delete' => Colors.red.shade700,
        _ => Theme.of(c).colorScheme.onSurfaceVariant,
      };

  String get _humanTime {
    final diff = DateTime.now().difference(log.createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return log.createdAt.toIso8601String().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final subject = log.entitySubject ?? '(${log.entityId?.substring(0, 8) ?? '–'})';
    final summary = '${log.userDisplay} ${log.action}d ${log.entityType} '
        '— $subject';
    final changed = log.changedFields;
    return ExpansionTile(
      leading: Icon(_icon, color: _color(context)),
      title: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        changed.isEmpty
            ? _humanTime
            : '$_humanTime  •  changed: ${changed.take(3).join(", ")}'
                '${changed.length > 3 ? "…" : ""}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (log.action == 'update') ...[
                Text(
                  'Changes',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                if (changed.isEmpty)
                  const Text('(no field changes detected)')
                else
                  for (final k in changed)
                    _DiffRow(
                      field: k,
                      before: log.before?[k]?.toString() ?? '∅',
                      after: log.after?[k]?.toString() ?? '∅',
                    ),
              ],
              if (log.action == 'insert' && log.after != null) ...[
                Text(
                  'Inserted row',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                _Json(log.after!),
              ],
              if (log.action == 'delete' && log.before != null) ...[
                Text(
                  'Deleted row',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                _Json(log.before!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.field,
    required this.before,
    required this.after,
  });
  final String field;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$field: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: before,
              style: const TextStyle(
                color: Colors.red,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const TextSpan(text: '  →  '),
            TextSpan(
              text: after,
              style: const TextStyle(color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}

class _Json extends StatelessWidget {
  const _Json(this.data);
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final entries = data.entries
        .where((e) => !{'created_at', 'updated_at', 'id'}.contains(e.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return SelectableText(
      entries.map((e) => '${e.key}: ${e.value}').join('\n'),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
    );
  }
}
