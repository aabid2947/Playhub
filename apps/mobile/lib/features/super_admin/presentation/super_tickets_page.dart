import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Maps a ticket priority to a badge tone. One mapping helper for the domain,
/// reused by the list and detail header (no hand-coloured indicators).
AppBadgeTone _priorityTone(String priority) {
  switch (priority) {
    case 'urgent':
      return AppBadgeTone.danger;
    case 'high':
      return AppBadgeTone.warning;
    case 'low':
      return AppBadgeTone.neutral;
    case 'normal':
    default:
      return AppBadgeTone.info;
  }
}

/// Maps a ticket status to a badge tone.
AppBadgeTone _statusTone(String status) {
  switch (status) {
    case 'open':
      return AppBadgeTone.info;
    case 'in_progress':
      return AppBadgeTone.brand;
    case 'waiting_on_user':
      return AppBadgeTone.warning;
    case 'resolved':
      return AppBadgeTone.success;
    case 'closed':
    default:
      return AppBadgeTone.neutral;
  }
}

/// Human label for an enum-ish status/priority token (`in_progress` → `In
/// progress`). Keeps the underlying value (sent to [updateTicket]) untouched.
String _humanize(String token) {
  if (token.isEmpty) return token;
  final spaced = token.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// The status transitions a staff member can apply, in workflow order.
const _statusOptions = <String>[
  'open',
  'in_progress',
  'waiting_on_user',
  'resolved',
  'closed',
];

/// Selectable priorities (low → urgent).
const _priorityOptions = <String>['low', 'normal', 'high', 'urgent'];

/// In-body status filter buckets. Five raw statuses don't fit an equal-width
/// [AppPillTabs] cleanly, so they're grouped into four readable segments;
/// "All" passes everything through.
enum _StatusFilter { all, open, active, closed }

extension _StatusFilterX on _StatusFilter {
  String get label => switch (this) {
        _StatusFilter.all => 'All',
        _StatusFilter.open => 'Open',
        _StatusFilter.active => 'Active',
        _StatusFilter.closed => 'Closed',
      };

  bool matches(String status) => switch (this) {
        _StatusFilter.all => true,
        _StatusFilter.open => status == 'open',
        _StatusFilter.active =>
          status == 'in_progress' || status == 'waiting_on_user',
        _StatusFilter.closed => status == 'resolved' || status == 'closed',
      };
}

/// Support tickets list — v1 "Sports-Light", archetype B (list).
///
/// App-bar-less tab body inside the super-admin shell (the shell owns the one
/// AppBar). An in-body header (title + result-count [AppBadge]) and an
/// [AppPillTabs] status filter sit above a column of ticket [AppCard] rows:
/// subject, academy, priority + status [AppBadge]s and an age cue. Tap a row →
/// the pushed [_TicketDetailPage].
///
/// Super-admin-only (gated upstream by `is_super_admin` RLS — no in-screen
/// capability gate).
class SuperTicketsPage extends ConsumerStatefulWidget {
  const SuperTicketsPage({super.key});

  @override
  ConsumerState<SuperTicketsPage> createState() => _SuperTicketsPageState();
}

class _SuperTicketsPageState extends ConsumerState<SuperTicketsPage> {
  _StatusFilter _filter = _StatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allTicketsProvider);
    // Resolve academy names for the row subtitle; falls back gracefully while
    // the academies list loads.
    final academies =
        ref.watch(allAcademiesProvider).valueOrNull ?? const <AcademyRow>[];
    final names = {for (final a in academies) a.id: a.name};

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
          child: AppPillTabs(
            tabs: [for (final f in _StatusFilter.values) f.label],
            index: _StatusFilter.values.indexOf(_filter),
            onChanged: (i) =>
                setState(() => _filter = _StatusFilter.values[i]),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const AppSkeletonList(),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(allTicketsProvider),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.support_agent_outlined,
                  title: 'No tickets',
                  subtitle: 'Academy support requests will show up here.',
                );
              }
              final list = rows
                  .where((t) => _filter.matches(t.status))
                  .toList(growable: false);
              if (list.isEmpty) {
                return AppEmptyState(
                  icon: Icons.support_agent_outlined,
                  title: 'No ${_filter.label.toLowerCase()} tickets',
                  subtitle: 'No support tickets match this filter.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(allTicketsProvider),
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
                    if (i == 0) return _ResultHeader(count: list.length);
                    final t = list[i - 1];
                    return _TicketCard(
                      ticket: t,
                      academyName: names[t.academyId],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _TicketDetailPage(ticket: t),
                        ),
                      ),
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
        title: 'Support tickets',
        icon: Icons.support_agent_outlined,
        trailing: AppBadge(
          text: count == 1 ? '1 ticket' : '$count tickets',
          tone: AppBadgeTone.brand,
        ),
      ),
    );
  }
}

/// One ticket row: a priority-tinted ticket icon tile → subject + academy line
/// → priority and status [AppBadge]s with an "age" cue. The whole card taps
/// through to the pushed [_TicketDetailPage].
class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.academyName,
    required this.onTap,
  });

  final SupportTicketRow ticket;
  final String? academyName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = colorFromName(ticket.priority);
    final academy = academyName ?? 'Academy';

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: AppListTile(
        wrapLeading: false,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            Icons.confirmation_number_outlined,
            color: tint,
            size: 20,
          ),
        ),
        title: Text(
          ticket.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                academy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppBadge(
                    text: _humanize(ticket.status),
                    tone: _statusTone(ticket.status),
                  ),
                  AppBadge(
                    text: _humanize(ticket.priority),
                    tone: _priorityTone(ticket.priority),
                  ),
                  Text(
                    _ageLabel(ticket.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A compact "raised N ago" age cue derived from [createdAt].
  String _ageLabel(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

class _TicketDetailPage extends ConsumerStatefulWidget {
  const _TicketDetailPage({required this.ticket});
  final SupportTicketRow ticket;

  @override
  ConsumerState<_TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends ConsumerState<_TicketDetailPage> {
  final _reply = TextEditingController();
  bool _busy = false;

  // Tracks status/priority/assignee locally so the controls reflect a
  // just-applied change without popping the page (the list still re-reads on
  // invalidate).
  late String _status = widget.ticket.status;
  late String _priority = widget.ticket.priority;
  late String? _assignedTo = widget.ticket.assignedTo;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(superAdminRepoProvider)
          .postStaffReply(
            ticketId: widget.ticket.id,
            academyId: widget.ticket.academyId,
            body: body,
          );
      _reply.clear();
      ref.invalidate(ticketMessagesProvider(widget.ticket.id));
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String status) async {
    if (status == _status) return;
    try {
      await ref
          .read(superAdminRepoProvider)
          .updateTicket(widget.ticket.id, status: status);
      ref.invalidate(allTicketsProvider);
      if (!mounted) return;
      setState(() => _status = status);
      AppSnackbar.success(context, 'Marked ${_humanize(status)}.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _setPriority(String priority) async {
    if (priority == _priority) return;
    try {
      await ref
          .read(superAdminRepoProvider)
          .updateTicket(widget.ticket.id, priority: priority);
      ref.invalidate(allTicketsProvider);
      if (!mounted) return;
      setState(() => _priority = priority);
      AppSnackbar.success(context, 'Priority set to ${_humanize(priority)}.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _toggleAssign() async {
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) return;
    final mineNow = _assignedTo == myId;
    final next = mineNow ? null : myId;
    try {
      await ref
          .read(superAdminRepoProvider)
          .setTicketAssignee(widget.ticket.id, next);
      ref.invalidate(allTicketsProvider);
      if (!mounted) return;
      setState(() => _assignedTo = next);
      AppSnackbar.success(context, mineNow ? 'Unassigned.' : 'Assigned to you.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('dd MMM yyyy · HH:mm');
    final msgsAsync = ref.watch(ticketMessagesProvider(widget.ticket.id));
    final myId = ref.watch(currentUserIdProvider);
    final assignedToMe = _assignedTo != null && _assignedTo == myId;
    final academies =
        ref.watch(allAcademiesProvider).valueOrNull ?? const <AcademyRow>[];
    final academyName =
        academies.where((a) => a.id == widget.ticket.academyId).firstOrNull?.name;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Archetype-C entity hero: a navy band with the back button,
                // the ticket subject + academy, and status/priority glass chips.
                _Hero(
                  subject: widget.ticket.subject,
                  academyName: academyName,
                  status: _status,
                  priority: _priority,
                  raisedLabel: 'Raised ${df.format(widget.ticket.createdAt)}',
                  onBack: () => Navigator.of(context).pop(),
                ),
                // Body overlaps the hero band upward, v1-style.
                Transform.translate(
                  offset: const Offset(0, -AppSpacing.xl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AppSectionHeader(
                          title: 'Original ticket',
                          icon: Icons.subject_outlined,
                        ),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.ticket.category != null) ...[
                                AppBadge(
                                  text: _humanize(widget.ticket.category!),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                              Text(
                                widget.ticket.body,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const AppSectionHeader(
                          title: 'Manage',
                          icon: Icons.tune_outlined,
                        ),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Status control — shows current state (badge),
                              // and on tap offers the transitions with the
                              // active one ticked.
                              _ControlRow(
                                label: 'Status',
                                child: PopupMenuButton<String>(
                                  tooltip: 'Change status',
                                  onSelected: _setStatus,
                                  itemBuilder: (_) => [
                                    for (final s in _statusOptions)
                                      PopupMenuItem<String>(
                                        value: s,
                                        child: _MenuChoice(
                                          label: _humanize(s),
                                          selected: s == _status,
                                        ),
                                      ),
                                  ],
                                  child: _BadgeTrigger(
                                    badge: AppBadge(
                                      text: _humanize(_status),
                                      tone: _statusTone(_status),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const Divider(height: 1),
                              const SizedBox(height: AppSpacing.sm),
                              _ControlRow(
                                label: 'Priority',
                                child: PopupMenuButton<String>(
                                  tooltip: 'Change priority',
                                  onSelected: _setPriority,
                                  itemBuilder: (_) => [
                                    for (final p in _priorityOptions)
                                      PopupMenuItem<String>(
                                        value: p,
                                        child: _MenuChoice(
                                          label: _humanize(p),
                                          selected: p == _priority,
                                        ),
                                      ),
                                  ],
                                  child: _BadgeTrigger(
                                    badge: AppBadge(
                                      text: _humanize(_priority),
                                      tone: _priorityTone(_priority),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const Divider(height: 1),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Icon(
                                    Icons.assignment_ind_outlined,
                                    size: 18,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      assignedToMe
                                          ? 'Assigned to you'
                                          : (_assignedTo == null
                                              ? 'Unassigned'
                                              : 'Assigned to another staffer'),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed:
                                        myId == null ? null : _toggleAssign,
                                    child: Text(
                                      assignedToMe ? 'Unassign' : 'Assign to me',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const AppSectionHeader(
                          title: 'Replies',
                          icon: Icons.forum_outlined,
                        ),
                        msgsAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpacing.lg,
                            ),
                            child: AppLoading(),
                          ),
                          error: (e, _) => AppErrorView(
                            message: friendlyError(e),
                            onRetry: () => ref.invalidate(
                              ticketMessagesProvider(widget.ticket.id),
                            ),
                          ),
                          data: (msgs) {
                            if (msgs.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: AppSpacing.md,
                                ),
                                child: AppEmptyState(
                                  icon: Icons.chat_bubble_outline,
                                  title: 'No replies yet',
                                  subtitle:
                                      'Your reply will start the conversation.',
                                ),
                              );
                            }
                            return Column(
                              children: [
                                for (final m in msgs)
                                  _ReplyBubble(
                                    body: m.body,
                                    isStaff: m.isStaff,
                                    timestamp: df.format(m.createdAt),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Pinned reply composer.
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.dividerColor),
                ),
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: AppFormField(
                      controller: _reply,
                      hint: 'Staff reply…',
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: 'Send reply',
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    onPressed: _busy ? null : _send,
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

/// Archetype-C navy hero for a ticket: back button, the subject + academy
/// identity, and a row of glass chips summarising status · priority, plus the
/// raised-at line.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.subject,
    required this.academyName,
    required this.status,
    required this.priority,
    required this.raisedLabel,
    required this.onBack,
  });

  final String subject;
  final String? academyName;
  final String status;
  final String priority;
  final String raisedLabel;
  final VoidCallback onBack;

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
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: onBack,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            subject,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          if (academyName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  Icons.school_outlined,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    academyName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppGlassChip(_humanize(status), icon: Icons.flag_rounded),
              AppGlassChip(
                _humanize(priority),
                icon: Icons.priority_high_rounded,
              ),
              AppGlassChip(raisedLabel, icon: Icons.schedule_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labeled row in the Manage card: a leading label that fills the row, and a
/// trailing interactive control (a badge-trigger popup).
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        child,
      ],
    );
  }
}

/// The tappable trigger for a status/priority popup: the current-value badge
/// plus a dropdown caret.
class _BadgeTrigger extends StatelessWidget {
  const _BadgeTrigger({required this.badge});
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        Icon(
          Icons.arrow_drop_down,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// A popup-menu choice with a radio glyph reflecting whether it's the active
/// value.
class _MenuChoice extends StatelessWidget {
  const _MenuChoice({required this.label, required this.selected});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          size: 18,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}

/// A single reply in the thread. Staff replies sit on the right with a brand
/// tint; academy replies sit on the left. Each shows an author avatar + label +
/// time so the conversation is unambiguous.
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({
    required this.body,
    required this.isStaff,
    required this.timestamp,
  });

  final String body;
  final bool isStaff;
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = isStaff ? 'Support staff' : 'Academy';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: isStaff ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            color: isStaff ? theme.colorScheme.primaryContainer : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppAvatar(author, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      author,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: AppType.semibold,
                        color: isStaff
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      timestamp,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isStaff
                            ? theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isStaff
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
