import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';
import 'package:playhub/features/leads/presentation/lead_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Status → badge tone, so the kanban and lead detail tell the same colour
/// story. Kept local since it's the only place leads render a status pill.
AppBadgeTone _toneFor(LeadStatus status) {
  switch (status) {
    case LeadStatus.newLead:
      return AppBadgeTone.info;
    case LeadStatus.contacted:
      return AppBadgeTone.neutral;
    case LeadStatus.interested:
      return AppBadgeTone.brand;
    case LeadStatus.trialScheduled:
      return AppBadgeTone.warning;
    case LeadStatus.converted:
      return AppBadgeTone.success;
    case LeadStatus.lost:
      return AppBadgeTone.danger;
  }
}

/// Six-column kanban scrolling horizontally. Each column holds the leads in
/// that status; tap a card → detail page. Pushed page, so it keeps its AppBar;
/// the v1 hero band sits beneath it and the board overlaps upward.
class LeadsKanbanPage extends ConsumerWidget {
  const LeadsKanbanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadsListProvider);
    final caps = ref.watch(capabilitiesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(leadsListProvider),
          ),
        ],
      ),
      // Creating a lead is gated — only roles with manageLeads see the FAB
      // (RLS is the real gate; this just hides the entry point).
      floatingActionButton: caps.manageLeads
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New lead'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LeadFormPage()),
              ),
            )
          : null,
      body: async.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(leadsListProvider),
        ),
        data: (leads) {
          if (leads.isEmpty) {
            return const AppEmptyState(
              icon: Icons.people_outline,
              title: 'No leads yet',
              subtitle: 'Capture an enquiry and track it through to enrolment.',
            );
          }
          return _Board(leads: leads);
        },
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.leads});
  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final byStatus = <LeadStatus, List<Lead>>{
      for (final s in LeadStatus.kanbanOrder) s: <Lead>[],
    };
    for (final l in leads) {
      // Skip leads whose status isn't part of the kanban view (e.g. a new
      // enum value added on the DB side that the app doesn't render yet).
      final column = byStatus[l.status];
      if (column == null) continue;
      column.add(l);
    }

    // Funnel summary for the hero strip: everything still in play (not yet
    // converted or lost) and the two terminal outcomes.
    final converted = byStatus[LeadStatus.converted]?.length ?? 0;
    final lost = byStatus[LeadStatus.lost]?.length ?? 0;
    final active = leads.length - converted - lost;

    return Column(
      children: [
        AppGradientHeader(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl + AppSpacing.md,
          ),
          child: AppHeroStatRow(
            stats: [
              ('$active', 'In funnel'),
              ('$converted', 'Converted'),
              ('${leads.length}', 'Total'),
            ],
          ),
        ),
        // The kanban overlaps the hero band upward, v1-style.
        Expanded(
          child: Transform.translate(
            offset: const Offset(0, -AppSpacing.lg),
            child: _Lanes(byStatus: byStatus),
          ),
        ),
      ],
    );
  }
}

/// The horizontally-scrolling lane strip. Pulled out so the hero stays fixed
/// while the columns page sideways underneath it.
class _Lanes extends StatelessWidget {
  const _Lanes({required this.byStatus});
  final Map<LeadStatus, List<Lead>> byStatus;

  @override
  Widget build(BuildContext context) {
    // Size each column so a phone shows roughly one column plus a peek of the
    // next — wide enough for scannable cards, narrow enough to invite the
    // horizontal swipe. Capped so it doesn't balloon on tablets.
    final width = MediaQuery.sizeOf(context).width;
    final columnWidth = (width - AppSpacing.lg * 2 - AppSpacing.md) * 0.82;
    final clampedWidth = columnWidth.clamp(240.0, 320.0);

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const PageScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: LeadStatus.kanbanOrder.length,
      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
      itemBuilder: (context, i) {
        final status = LeadStatus.kanbanOrder[i];
        return _Column(
          status: status,
          leads: byStatus[status] ?? const [],
          width: clampedWidth,
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.status,
    required this.leads,
    required this.width,
  });
  final LeadStatus status;
  final List<Lead> leads;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(status: status, count: leads.length),
          const SizedBox(height: AppSpacing.md),
          if (leads.isEmpty)
            const _ColumnEmpty()
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: leads.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) => _Card(lead: leads[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status, required this.count});
  final LeadStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentFor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          // A small tone dot so each lane reads as its own colour at a glance.
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              status.label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: AppType.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppBadge(text: '$count', tone: _toneFor(status)),
        ],
      ),
    );
  }
}

/// The foreground colour for a status' tone — used for the lane header dot so
/// the dot matches the count badge without re-deriving it inside the badge.
Color _accentFor(BuildContext context, LeadStatus status) {
  final scheme = Theme.of(context).colorScheme;
  final semantics = AppSemanticColors.of(context);
  switch (_toneFor(status)) {
    case AppBadgeTone.success:
      return semantics.success;
    case AppBadgeTone.warning:
      return semantics.warning;
    case AppBadgeTone.danger:
      return semantics.danger;
    case AppBadgeTone.info:
      return semantics.info;
    case AppBadgeTone.brand:
      return scheme.primary;
    case AppBadgeTone.neutral:
      return scheme.onSurfaceVariant;
  }
}

/// Mini empty state for a column with no leads — a soft outlined panel rather
/// than a low-contrast dash, so an empty stage reads as "nothing here yet".
class _ColumnEmpty extends StatelessWidget {
  const _ColumnEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No leads here',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sportLabel = ref.watch(sportDisplayProvider((sportId: lead.sportId)));
    final contact = lead.phone ?? lead.email;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => context.push('/leads/${lead.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name, with the status pill trailing.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(lead.displayName, size: 36),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.displayName,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: AppType.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sportLabel != '—' || contact != null)
                      Text(
                        [
                          if (sportLabel != '—') sportLabel,
                          if (contact != null) contact,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppBadge(text: lead.status.label, tone: _toneFor(lead.status)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.flag_outlined,
                size: AppFontSize.base,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  lead.source.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (lead.nextFollowupAt != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _FollowupChip(when: lead.nextFollowupAt!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Next-followup pill. Overdue follow-ups are flagged with a danger tone and an
/// explicit label so the urgency isn't carried by colour alone.
class _FollowupChip extends StatelessWidget {
  const _FollowupChip({required this.when});
  final DateTime when;

  @override
  Widget build(BuildContext context) {
    final overdue = when.isBefore(DateTime.now());
    final date = '${when.day}/${when.month}';
    return AppBadge(
      text: overdue ? 'Overdue · $date' : date,
      tone: overdue ? AppBadgeTone.danger : AppBadgeTone.neutral,
      icon: overdue ? Icons.event_busy_outlined : Icons.event_outlined,
    );
  }
}
