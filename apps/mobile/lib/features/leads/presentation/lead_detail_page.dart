import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';
import 'package:playhub/features/leads/presentation/lead_convert_sheet.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

final _dateFmt = DateFormat('dd MMM yyyy · HH:mm');
final _dayFmt = DateFormat('dd MMM yyyy');

/// Maps a [LeadStatus] to a badge tone so status is conveyed by color + label
/// (never color alone) and adapts to light/dark via [AppSemanticColors].
AppBadgeTone _statusTone(LeadStatus status) {
  switch (status) {
    case LeadStatus.newLead:
    case LeadStatus.contacted:
      return AppBadgeTone.info;
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

/// A short relative-time label ("just now", "3h ago", "2d ago"); for older
/// entries the absolute date carries the load.
String _relativeTime(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return _dayFmt.format(when);
}

/// Lead detail — archetype C. An entity-colored gradient hero (sport-derived)
/// with the status badge + glass chips, a floating 3-up mini-stat row, then the
/// status/actions zone, contact info rows, and a real activity timeline. The
/// note composer is pinned above the keyboard at the bottom.
class LeadDetailPage extends ConsumerWidget {
  const LeadDetailPage({required this.leadId, super.key});
  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leadAsync = ref.watch(leadByIdProvider(leadId));
    final actsAsync = ref.watch(leadActivitiesProvider(leadId));
    return Scaffold(
      body: leadAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(leadByIdProvider(leadId)),
        ),
        data: (lead) {
          if (lead == null) {
            return const AppEmptyState(
              icon: Icons.person_search_outlined,
              title: 'Lead not found',
              subtitle: 'It may have been converted or removed.',
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _Hero(lead: lead),
                    Transform.translate(
                      offset: const Offset(0, -AppSpacing.lg),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MiniStats(lead: lead),
                            if (lead.notes != null) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _Summary(text: lead.notes!),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _StatusActions(lead: lead),
                            const SizedBox(height: AppSpacing.lg),
                            _Contact(lead: lead),
                            const SizedBox(height: AppSpacing.lg),
                            const AppSectionHeader(
                              title: 'Activity',
                              icon: Icons.history_rounded,
                            ),
                            actsAsync.when(
                              loading: () => const AppSkeletonList(count: 3),
                              error: (e, _) => Text(
                                friendlyError(e),
                                style: TextStyle(
                                  color: AppSemanticColors.of(context).danger,
                                ),
                              ),
                              data: (acts) {
                                if (acts.isEmpty) {
                                  return const _ActivityEmpty();
                                }
                                return _ActivityTimeline(activities: acts);
                              },
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _NoteComposer(leadId: lead.id),
            ],
          );
        },
      ),
    );
  }
}

/// The sport-colored gradient hero: back button + status badge, a big gradient
/// avatar, the lead name, and source/sport/age glass chips.
class _Hero extends ConsumerWidget {
  const _Hero({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: lead.sportId)),
    );
    // Entity hero: tint the gradient from the lead name so each lead reads as
    // its own card (pair = lighter→base of a deterministic accent color).
    final c = colorFromName(lead.displayName);
    return AppGradientHeader(
      colors: [c.withValues(alpha: 0.92), c],
      child: Column(
        children: [
          Row(
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              AppBadge(
                text: lead.status.label,
                tone: _statusTone(lead.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppAvatar(lead.displayName, size: 76, color: Colors.white),
          const SizedBox(height: AppSpacing.md),
          Text(
            lead.displayName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              AppGlassChip(lead.source.label, icon: Icons.input_rounded),
              if (sportLabel != '—')
                AppGlassChip(sportLabel, icon: Icons.sports_rounded),
              if (lead.age != null)
                AppGlassChip('${lead.age} yrs', icon: Icons.cake_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

/// Floating 3-up mini-stat row that overlaps the hero band: pipeline stage,
/// trial date (if any), and the date the lead came in.
class _MiniStats extends StatelessWidget {
  const _MiniStats({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final semantics = AppSemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final trial = lead.trialScheduledAt?.toLocal();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _MiniStat(
            icon: Icons.flag_rounded,
            value: lead.status.label,
            label: 'Stage',
            tint: scheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MiniStat(
            icon: Icons.event_rounded,
            value: trial == null ? '—' : _dayFmt.format(trial),
            label: 'Trial',
            tint: trial == null ? scheme.onSurfaceVariant : semantics.warning,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MiniStat(
            icon: Icons.schedule_rounded,
            value: _relativeTime(lead.createdAt),
            label: 'Added',
            tint: scheme.secondary,
          ),
        ),
      ],
    );
  }
}

/// A compact floating stat card used in the overlapping mini-stat row.
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Column(
        children: [
          Icon(icon, color: tint, size: 22),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: tint,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The lead's free-text notes, shown as a quiet summary card under the hero.
class _Summary extends StatelessWidget {
  const _Summary({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusActions extends ConsumerWidget {
  const _StatusActions({required this.lead});
  final Lead lead;

  Future<void> _setStatus(WidgetRef ref, LeadStatus s) async {
    final repo = await ref.read(leadsRepoProvider.future);
    await repo?.updateStatus(lead.id, s);
    ref
      ..invalidate(leadByIdProvider(lead.id))
      ..invalidate(leadActivitiesProvider(lead.id))
      ..invalidate(leadsListProvider);
  }

  Future<void> _scheduleTrial(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (time == null) return;
    final dt = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time.hour,
      time.minute,
    );
    final repo = await ref.read(leadsRepoProvider.future);
    await repo?.scheduleTrial(lead.id, dt);
    ref
      ..invalidate(leadByIdProvider(lead.id))
      ..invalidate(leadActivitiesProvider(lead.id))
      ..invalidate(leadsListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final converted = lead.status == LeadStatus.converted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Pipeline stage',
          icon: Icons.timeline_rounded,
        ),
        AppCard(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in LeadStatus.kanbanOrder)
                if (s != LeadStatus.converted)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: lead.status == s,
                    onSelected: (sel) {
                      if (sel) _setStatus(ref, s);
                    },
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Bottom action row: secondary outlined (schedule) + primary filled
        // (convert). Convert is disabled once the lead is already converted.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 18),
                label: const Text('Schedule trial'),
                onPressed: () => _scheduleTrial(context, ref),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Convert'),
                onPressed: converted
                    ? null
                    : () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => LeadConvertSheet(lead: lead),
                        );
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (lead.phone != null)
        _ContactRow(icon: Icons.phone_outlined, label: 'Phone', value: lead.phone!),
      if (lead.email != null)
        _ContactRow(icon: Icons.email_outlined, label: 'Email', value: lead.email!),
      if (lead.parentName != null)
        _ContactRow(
          icon: Icons.family_restroom_outlined,
          value: lead.parentName!,
          label: 'Parent',
        ),
      if (lead.trialScheduledAt != null)
        _ContactRow(
          icon: Icons.event_available_outlined,
          label: 'Trial scheduled',
          value: _dateFmt.format(lead.trialScheduledAt!.toLocal()),
        ),
      if (lead.nextFollowupAt != null)
        _ContactRow(
          icon: Icons.alarm_outlined,
          label: 'Next follow-up',
          value: _dateFmt.format(lead.nextFollowupAt!.toLocal()),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Contact',
          icon: Icons.contact_phone_outlined,
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'No contact details on file.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      rows[i],
                      if (i != rows.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// An info row: leading tinted icon, a small label and the value beneath it.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          Icon(
            Icons.history_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No activity yet. Add a note below.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical timeline: each entry is a dotted node joined by a connector line,
/// the kind icon, its content, and a relative + absolute timestamp.
class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.activities});
  final List<LeadActivity> activities;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < activities.length; i++)
            _TimelineEntry(
              activity: activities[i],
              isFirst: i == 0,
              isLast: i == activities.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.activity,
    required this.isFirst,
    required this.isLast,
  });

  final LeadActivity activity;
  final bool isFirst;
  final bool isLast;

  static const _iconFor = <String, IconData>{
    'note': Icons.note_outlined,
    'status_change': Icons.swap_horiz,
    'call_logged': Icons.call,
    'email_sent': Icons.outgoing_mail,
    'sms_sent': Icons.sms,
    'trial_scheduled': Icons.event,
    'reminder_sent': Icons.alarm,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final when = activity.createdAt.toLocal();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline rail: connector above, node dot, connector below.
          Column(
            children: [
              SizedBox(
                height: AppSpacing.xs,
                child: VerticalDivider(
                  width: AppSpacing.lg,
                  color: isFirst ? Colors.transparent : scheme.outlineVariant,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconFor[activity.kind] ?? Icons.event_note,
                  size: 16,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              Expanded(
                child: VerticalDivider(
                  width: AppSpacing.lg,
                  color: isLast ? Colors.transparent : scheme.outlineVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.content ?? activity.kind,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${_relativeTime(when)} · ${_dateFmt.format(when)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned composer that rides above the keyboard (Scaffold resizes the body),
/// kept inside a [SafeArea] so it clears the system gesture inset.
class _NoteComposer extends ConsumerStatefulWidget {
  const _NoteComposer({required this.leadId});
  final String leadId;

  @override
  ConsumerState<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends ConsumerState<_NoteComposer> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    final repo = await ref.read(leadsRepoProvider.future);
    await repo?.addNote(widget.leadId, text);
    _ctrl.clear();
    if (mounted) setState(() => _busy = false);
    ref.invalidate(leadActivitiesProvider(widget.leadId));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: AppShadows.floating,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _ctrl,
                    hint: 'Add a note',
                    textInputAction: TextInputAction.send,
                    onFieldSubmitted: (_) => _busy ? null : _add(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _busy ? null : _add,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
