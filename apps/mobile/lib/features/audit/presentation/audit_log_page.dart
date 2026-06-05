import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/audit/data/audit_log.dart';
import 'package:playhub/features/audit/data/audit_log_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(auditLogsProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(auditLogsProvider),
        ),
        data: (logs) {
          if (logs.isEmpty) {
            return const AppEmptyState(
              icon: Icons.history_outlined,
              title: 'No activity yet',
              subtitle: 'Changes to students, payments, and settings '
                  'show up here.',
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

  Color _color(BuildContext c) {
    final s = AppSemanticColors.of(c);
    return switch (log.action) {
      'insert' => s.success,
      'update' => s.info,
      'delete' => s.danger,
      _ => Theme.of(c).colorScheme.onSurfaceVariant,
    };
  }

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
    final subject =
        log.entitySubject ?? '(${log.entityId?.substring(0, 8) ?? '–'})';
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (log.action == 'update') ...[
                Text(
                  'Changes',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
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
                const SizedBox(height: AppSpacing.xs),
                _Json(log.after!),
              ],
              if (log.action == 'delete' && log.before != null) ...[
                Text(
                  'Deleted row',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
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
    final semantics = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$field: ',
              style: const TextStyle(fontWeight: AppType.semibold),
            ),
            TextSpan(
              text: before,
              style: TextStyle(
                color: semantics.danger,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const TextSpan(text: '  →  '),
            TextSpan(
              text: after,
              style: TextStyle(color: semantics.success),
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
