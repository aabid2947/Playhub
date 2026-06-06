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
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              // One extra item: a footer that makes the 50-row cap explicit.
              itemCount: logs.length + 1,
              separatorBuilder: (_, index) => index == logs.length - 1
                  ? const SizedBox.shrink()
                  : const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i == logs.length) {
                  return _LoadMoreFooter(count: logs.length);
                }
                return _LogTile(log: logs[i]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// Maps an audit action to its row icon, badge label, and badge tone.
({IconData icon, String label, AppBadgeTone tone}) _actionStyle(String action) {
  switch (action) {
    case 'insert':
      return (
        icon: Icons.add_circle_outline,
        label: 'Created',
        tone: AppBadgeTone.success,
      );
    case 'update':
      return (
        icon: Icons.edit_outlined,
        label: 'Updated',
        tone: AppBadgeTone.info,
      );
    case 'delete':
      return (
        icon: Icons.delete_outline,
        label: 'Deleted',
        tone: AppBadgeTone.danger,
      );
    default:
      return (
        icon: Icons.info_outline,
        label: action,
        tone: AppBadgeTone.neutral,
      );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
  final AuditLog log;

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final style = _actionStyle(log.action);

    final subject =
        log.entitySubject ?? '(${log.entityId?.substring(0, 8) ?? '–'})';
    final changed = log.changedFields;

    // Tinted leading icon box mirrors the AppListTile leading rhythm.
    final leading = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(style.icon, size: 20, color: _iconColor(semantics, scheme)),
    );

    // Subtitle: relative time, plus a field-change count for updates.
    final subtitleText = changed.isEmpty
        ? _humanTime
        : '$_humanTime  •  ${changed.length} '
            'field${changed.length == 1 ? '' : 's'} changed';

    return ExpansionTile(
      leading: leading,
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              log.userDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: AppType.semibold),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppBadge(text: style.label, tone: style.tone),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Entity type + subject as distinct, scannable elements.
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: log.entityType,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: AppType.medium,
                    ),
                  ),
                  const TextSpan(text: '  ·  '),
                  TextSpan(text: subject),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              subtitleText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      children: [
        _DiffPanel(log: log, changed: changed),
      ],
    );
  }

  Color _iconColor(AppSemanticColors semantics, ColorScheme scheme) {
    return switch (log.action) {
      'insert' => semantics.success,
      'update' => semantics.info,
      'delete' => semantics.danger,
      _ => scheme.onSurfaceVariant,
    };
  }
}

/// The expanded body: a clean diff for updates, or the affected row otherwise.
class _DiffPanel extends StatelessWidget {
  const _DiffPanel({required this.log, required this.changed});
  final AuditLog log;
  final List<String> changed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget body;
    final String header;
    if (log.action == 'update') {
      header = 'Changes';
      body = changed.isEmpty
          ? Text(
              '(no field changes detected)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final k in changed)
                  _DiffRow(
                    field: k,
                    before: log.before?[k]?.toString() ?? '∅',
                    after: log.after?[k]?.toString() ?? '∅',
                  ),
              ],
            );
    } else if (log.action == 'insert' && log.after != null) {
      header = 'Inserted row';
      body = _Json(log.after!);
    } else if (log.action == 'delete' && log.before != null) {
      header = 'Deleted row';
      body = _Json(log.before!);
    } else {
      // Nothing structured to show (e.g. a delete with no captured row).
      return const SizedBox.shrink();
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(header, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          body,
        ],
      ),
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
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: AppType.semibold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: before,
                  style: TextStyle(
                    color: semantics.danger,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const TextSpan(text: '   →   '),
                TextSpan(
                  text: after,
                  style: TextStyle(color: semantics.success),
                ),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Json extends StatelessWidget {
  const _Json(this.data);
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = data.entries
        .where((e) => !{'created_at', 'updated_at', 'id'}.contains(e.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return SelectableText(
      entries.map((e) => '${e.key}: ${e.value}').join('\n'),
      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
    );
  }
}

/// Footer that makes the "latest 50" cap explicit instead of a silent limit.
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Center(
        child: Text(
          'Showing the latest $count entries · pull to refresh',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
