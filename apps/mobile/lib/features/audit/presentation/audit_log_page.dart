import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/audit/data/audit_log.dart';
import 'package:playhub/features/audit/data/audit_log_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Tenant activity log — v1 "Sports-Light".
///
/// A pushed page (archetype C/H hybrid): a navy hero summarises the captured
/// window, then scannable [AppCard] rows (actor · action · entity + an
/// action-kind [AppBadge]) expand to a clean before→after diff. The "latest 50"
/// cap is surfaced as an explicit footer cue, not a silent limit.
///
/// Presentation-only: the read provider, its 50-row cap, and the academy-scoped
/// RLS query are unchanged.
class AuditLogPage extends ConsumerWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auditLogsProvider);

    return Scaffold(
      body: async.when(
        loading: () => Column(
          children: [
            _Hero(
              total: null,
              created: 0,
              updated: 0,
              deleted: 0,
              onRefresh: () => ref.invalidate(auditLogsProvider),
            ),
            const Expanded(child: AppSkeletonList()),
          ],
        ),
        error: (e, _) => Column(
          children: [
            _Hero(
              total: null,
              created: 0,
              updated: 0,
              deleted: 0,
              onRefresh: () => ref.invalidate(auditLogsProvider),
            ),
            Expanded(
              child: AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(auditLogsProvider),
              ),
            ),
          ],
        ),
        data: (logs) {
          final created = logs.where((l) => l.action == 'insert').length;
          final updated = logs.where((l) => l.action == 'update').length;
          final deleted = logs.where((l) => l.action == 'delete').length;

          final hero = _Hero(
            total: logs.length,
            created: created,
            updated: updated,
            deleted: deleted,
            onRefresh: () => ref.invalidate(auditLogsProvider),
          );

          if (logs.isEmpty) {
            return Column(
              children: [
                hero,
                const Expanded(
                  child: AppEmptyState(
                    icon: Icons.history_outlined,
                    title: 'No activity yet',
                    subtitle: 'Changes to students, payments, and settings '
                        'show up here.',
                  ),
                ),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(auditLogsProvider),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              // Header hero + one row per log + a footer cue for the 50-cap.
              itemCount: logs.length + 2,
              itemBuilder: (_, i) {
                if (i == 0) return hero;
                if (i == logs.length + 1) {
                  return _LoadMoreFooter(count: logs.length);
                }
                final log = logs[i - 1];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: _LogTile(log: log),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Navy hero band: a back control, title, refresh, and a translucent summary of
/// the captured window broken down by action kind.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.total,
    required this.created,
    required this.updated,
    required this.deleted,
    required this.onRefresh,
  });

  /// Total entries in the current window; null while loading/erroring.
  final int? total;
  final int created;
  final int updated;
  final int deleted;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppGradientHeader(
      colors: AppPalette.navyGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Activity log',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppCircleIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onTap: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppHeroStatRow(
            stats: [
              ('${total ?? '–'}', 'Entries'),
              ('$created', 'Created'),
              ('$updated', 'Updated'),
              ('$deleted', 'Deleted'),
            ],
          ),
        ],
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

/// A scannable, expandable row: gradient actor avatar → actor · entity + an
/// action-kind badge → relative time, expanding to a clean diff in [_DiffPanel].
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
    final style = _actionStyle(log.action);

    final subject =
        log.entitySubject ?? '(${log.entityId?.substring(0, 8) ?? '–'})';
    final changed = log.changedFields;

    // Subtitle: entity type · subject, then time + an optional field-change
    // count for updates.
    final metaText = changed.isEmpty
        ? _humanTime
        : '$_humanTime  •  ${changed.length} '
            'field${changed.length == 1 ? '' : 's'} changed';

    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        // Strip the ExpansionTile's default divider lines so it sits clean
        // inside the card.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          leading: AppAvatar(log.userDisplay, size: 40),
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
              AppBadge(text: style.label, tone: style.tone, icon: style.icon),
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
                  metaText,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          children: [
            _DiffPanel(log: log, changed: changed),
          ],
        ),
      ),
    );
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
    final scheme = theme.colorScheme;

    final Widget body;
    final String header;
    final IconData headerIcon;
    if (log.action == 'update') {
      header = 'Changes';
      headerIcon = Icons.compare_arrows_rounded;
      body = changed.isEmpty
          ? Text(
              '(no field changes detected)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
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
      headerIcon = Icons.add_circle_outline;
      body = _Json(log.after!);
    } else if (log.action == 'delete' && log.before != null) {
      header = 'Deleted row';
      headerIcon = Icons.delete_outline;
      body = _Json(log.before!);
    } else {
      // Nothing structured to show (e.g. a delete with no captured row).
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(headerIcon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Text(header, style: theme.textTheme.labelLarge),
            ],
          ),
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
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        children: [
          Icon(
            Icons.history_toggle_off_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Showing the latest $count entries · pull to refresh for more',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
