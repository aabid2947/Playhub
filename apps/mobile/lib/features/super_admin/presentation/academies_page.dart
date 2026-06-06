import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class AcademiesPage extends ConsumerStatefulWidget {
  const AcademiesPage({super.key});

  @override
  ConsumerState<AcademiesPage> createState() => _AcademiesPageState();
}

class _AcademiesPageState extends ConsumerState<AcademiesPage> {
  String _query = '';

  /// Maps a subscription-status enum value to a badge tone + readable label.
  ({String label, AppBadgeTone tone}) _statusBadge(String status) {
    switch (status) {
      case 'active':
        return (label: 'Active', tone: AppBadgeTone.success);
      case 'trial':
        return (label: 'Trial', tone: AppBadgeTone.info);
      case 'past_due':
        return (label: 'Past due', tone: AppBadgeTone.warning);
      case 'suspended':
        return (label: 'Suspended', tone: AppBadgeTone.danger);
      case 'cancelled':
        return (label: 'Cancelled', tone: AppBadgeTone.neutral);
      default:
        return (label: status, tone: AppBadgeTone.neutral);
    }
  }

  Future<void> _confirmToggle(AcademyRow academy, bool enable) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(enable ? 'Enable academy?' : 'Disable academy?'),
        content: Text(
          enable
              ? 'Re-enable "${academy.name}"? Its members will regain access.'
              : 'Disable "${academy.name}"? Everyone in this academy will lose '
                  'access until it is re-enabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(enable ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(superAdminRepoProvider)
        .setAcademyActive(academy.id, enable);
    ref.invalidate(allAcademiesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allAcademiesProvider);
    final df = DateFormat('dd MMM yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: AppFormField(
            hint: 'Search academies by name',
            prefixIcon: const Icon(Icons.search),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const AppSkeletonList(),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(allAcademiesProvider),
            ),
            data: (rows) {
              final list = (_query.isEmpty
                      ? rows
                      : rows.where(
                          (a) => a.name.toLowerCase().contains(_query),
                        ))
                  .toList(growable: false);
              if (list.isEmpty) {
                return AppEmptyState(
                  icon: Icons.school_outlined,
                  title:
                      _query.isEmpty ? 'No academies' : 'No matching academies',
                  subtitle: _query.isEmpty
                      ? null
                      : 'No academy name matches "$_query".',
                );
              }
              final theme = Theme.of(context);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      list.length == 1 ? '1 academy' : '${list.length} academies',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(allAcademiesProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final a = list[i];
                          final badge = _statusBadge(a.subscriptionStatus);
                          final isTrial = a.subscriptionStatus == 'trial';
                          return AppListTile(
                            leading: const Icon(Icons.school_outlined),
                            title: Text(a.name),
                            subtitle: Text(
                              isTrial && a.trialEndsAt != null
                                  ? 'Trial ends ${df.format(a.trialEndsAt!)}'
                                  : 'Created ${df.format(a.createdAt)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppBadge(text: badge.label, tone: badge.tone),
                                const SizedBox(width: AppSpacing.sm),
                                Switch(
                                  value: a.isActive,
                                  onChanged: (v) => _confirmToggle(a, v),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
