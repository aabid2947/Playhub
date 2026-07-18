import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/features/super_admin/presentation/academy_detail_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Academies list — v1 "Sports-Light", archetype B (list).
///
/// App-bar-less tab body inside the super-admin shell (the shell owns the one
/// AppBar). A search field + an in-body header (title + result-count
/// [AppBadge]) sit above a column of academy [AppCard] rows: gradient
/// [AppAvatar] + name, a subscription-status [AppBadge], an active/inactive
/// [AppBadge], and an enable/disable [Switch]. Tap a row → [AcademyDetailPage].
///
/// Super-admin-only (gated upstream by `is_super_admin` RLS — no in-screen
/// capability gate). The [Switch] keeps its confirmation dialog +
/// `setAcademyActive` call + `allAcademiesProvider` invalidate exactly.
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
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(allAcademiesProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, i) => i == 0
                      ? const SizedBox.shrink()
                      : const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return _ResultHeader(count: list.length);
                    }
                    final a = list[i - 1];
                    return _AcademyCard(
                      academy: a,
                      statusBadge: _statusBadge(a.subscriptionStatus),
                      onToggle: (v) => _confirmToggle(a, v),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// In-body list header: a navy section title with a brand-toned count badge.
class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppSectionHeader(
        title: 'Academies',
        icon: Icons.school_outlined,
        trailing: AppBadge(
          text: count == 1 ? '1 academy' : '$count academies',
          tone: AppBadgeTone.brand,
        ),
      ),
    );
  }
}

/// One academy row: gradient [AppAvatar] + name, a subscription-status badge,
/// an active/inactive badge, the created/trial line, and an enable/disable
/// [Switch]. The whole card taps through to [AcademyDetailPage].
class _AcademyCard extends StatelessWidget {
  const _AcademyCard({
    required this.academy,
    required this.statusBadge,
    required this.onToggle,
  });

  final AcademyRow academy;
  final ({String label, AppBadgeTone tone}) statusBadge;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('dd MMM yyyy');
    final isTrial = academy.subscriptionStatus == 'trial';
    final dateLine = isTrial && academy.trialEndsAt != null
        ? 'Trial ends ${df.format(academy.trialEndsAt!)}'
        : 'Created ${df.format(academy.createdAt)}';

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AcademyDetailPage(
            academyId: academy.id,
            initialName: academy.name,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(academy.name),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      academy.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: academy.isActive,
                onChanged: onToggle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppBadge(text: statusBadge.label, tone: statusBadge.tone),
              AppBadge(
                text: academy.isActive ? 'Active' : 'Inactive',
                tone:
                    academy.isActive ? AppBadgeTone.success : AppBadgeTone.danger,
                icon: academy.isActive
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
