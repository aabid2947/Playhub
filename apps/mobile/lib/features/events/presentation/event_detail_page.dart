import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/events/presentation/event_register_sheet.dart';
import 'package:playhub/features/events/presentation/event_results_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class EventDetailPage extends ConsumerWidget {
  const EventDetailPage({required this.eventId, super.key});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventByIdProvider(eventId));
    final regsAsync = ref.watch(eventRegistrationsProvider(eventId));
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final canManage =
        profile != null &&
        const [
          'academy_owner',
          'academy_admin',
          'center_admin',
          'head_coach',
        ].contains(profile.role);

    void refresh() => ref
      ..invalidate(eventByIdProvider(eventId))
      ..invalidate(eventRegistrationsProvider(eventId));

    return Scaffold(
      body: eventAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => SafeArea(
          child: AppErrorView(
            message: friendlyError(e),
            onRetry: refresh,
          ),
        ),
        data: (event) {
          if (event == null) {
            return const SafeArea(
              child: AppEmptyState(
                icon: Icons.event_busy_outlined,
                title: 'Not found',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Hero(
                  event: event,
                  regsAsync: regsAsync,
                  canManage: canManage,
                  onBack: () => Navigator.of(context).pop(),
                  onResults: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EventResultsPage(eventId: eventId),
                    ),
                  ),
                  onDelete: () => _confirmDelete(context, ref),
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
                        _MiniStatRow(event: event, regsAsync: regsAsync),
                        const SizedBox(height: AppSpacing.lg),
                        _DetailsSection(event: event),
                        if (canManage) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _StatusSection(event: event),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        _RegistrationsSection(
                          event: event,
                          regsAsync: regsAsync,
                          canManage: canManage,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Hard-delete the event after confirmation. Cascades to its registrations
  /// and results (FK on delete cascade). RLS limits this to admin tier +
  /// center_admin + head_coach, which is exactly the page's `canManage` gate.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this event?',
      message:
          'This permanently removes the event and all its registrations and '
          'results. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      final repo = await ref.read(eventsRepoProvider.future);
      if (repo == null) return;
      await repo.deleteEvent(eventId);
      ref.invalidate(eventsListProvider);
      if (context.mounted) {
        AppSnackbar.success(context, 'Event deleted.');
        Navigator.of(context).pop();
      }
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

AppBadgeTone _statusTone(EventStatus s) {
  switch (s) {
    case EventStatus.draft:
      return AppBadgeTone.neutral;
    case EventStatus.published:
      return AppBadgeTone.info;
    case EventStatus.registrationClosed:
      return AppBadgeTone.warning;
    case EventStatus.inProgress:
      return AppBadgeTone.success;
    case EventStatus.completed:
      return AppBadgeTone.brand;
    case EventStatus.cancelled:
      return AppBadgeTone.danger;
  }
}

/// A representative glyph per event kind, used in the hero mark.
IconData _kindIcon(EventKind kind) {
  switch (kind) {
    case EventKind.tournament:
      return Icons.emoji_events_rounded;
    case EventKind.workshop:
      return Icons.school_rounded;
    case EventKind.camp:
      return Icons.cabin_rounded;
    case EventKind.fixture:
      return Icons.sports_rounded;
    case EventKind.social:
      return Icons.celebration_rounded;
  }
}

/// Archetype-C entity hero: an event-kind-colored gradient band with the back
/// and (gated) manage circle buttons, a large kind glyph, the title, and a row
/// of glass chips summarising kind · status · registration state.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.event,
    required this.regsAsync,
    required this.canManage,
    required this.onBack,
    required this.onResults,
    required this.onDelete,
  });

  final EventEntry event;
  final AsyncValue<List<EventRegistration>> regsAsync;
  final bool canManage;
  final VoidCallback onBack;
  final VoidCallback onResults;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('EEE, dd MMM yyyy · h:mma');
    // Deterministic accent from the event kind so each kind reads consistently.
    final c = colorFromName(event.kind.label);
    return AppGradientHeader(
      colors: [c.withValues(alpha: 0.92), c],
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
              const Spacer(),
              if (canManage) ...[
                AppCircleIconButton(
                  icon: Icons.emoji_events_outlined,
                  tooltip: 'Results & certificates',
                  onTap: onResults,
                ),
                const SizedBox(width: AppSpacing.sm),
                AppCircleIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete event',
                  onTap: onDelete,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(_kindIcon(event.kind), color: Colors.white, size: 32),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            event.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            df.format(event.startsAt),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppGlassChip(event.kind.label, icon: _kindIcon(event.kind)),
              AppGlassChip(event.status.label, icon: Icons.flag_rounded),
              if (event.registrationOpen)
                const AppGlassChip(
                  'Registration open',
                  icon: Icons.how_to_reg_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A floating 3-up mini-stat strip overlapping the hero band: registered count,
/// capacity (or "Open"), and entry fee.
class _MiniStatRow extends StatelessWidget {
  const _MiniStatRow({required this.event, required this.regsAsync});

  final EventEntry event;
  final AsyncValue<List<EventRegistration>> regsAsync;

  @override
  Widget build(BuildContext context) {
    final semantics = AppSemanticColors.of(context);
    final regs = regsAsync.valueOrNull ?? const <EventRegistration>[];
    final active =
        regs.where((r) => r.status != 'cancelled').length;
    final feeLabel = event.feeAmount > 0
        ? '₹${event.feeAmount.toStringAsFixed(0)}'
        : 'Free';
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            icon: Icons.how_to_reg_rounded,
            value: '$active',
            label: 'Registered',
            color: AppPalette.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MiniStat(
            icon: Icons.groups_rounded,
            value: event.capacity == null ? 'Open' : '${event.capacity}',
            label: 'Capacity',
            color: AppPalette.brandPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MiniStat(
            icon: Icons.payments_rounded,
            value: feeLabel,
            label: 'Entry fee',
            color: event.feeAmount > 0 ? semantics.warning : semantics.success,
          ),
        ),
      ],
    );
  }
}

/// One compact KPI inside the floating overlap row.
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
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

/// The event's facts — schedule, location, fee, capacity, and description —
/// presented as labeled info rows under a section header.
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.event});
  final EventEntry event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('EEE, dd MMM yyyy · h:mma');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(
          title: 'Details',
          icon: Icons.event_note_outlined,
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: [
              _MetaRow(
                icon: Icons.event_outlined,
                label: 'Starts',
                value: df.format(event.startsAt),
              ),
              if (event.endsAt != null)
                _MetaRow(
                  icon: Icons.event_available_outlined,
                  label: 'Ends',
                  value: df.format(event.endsAt!),
                ),
              if (event.location != null && event.location!.isNotEmpty)
                _MetaRow(
                  icon: Icons.place_outlined,
                  label: 'Location',
                  value: event.location!,
                ),
              if (event.feeAmount > 0)
                _MetaRow(
                  icon: Icons.payments_outlined,
                  label: 'Fee',
                  value: '₹${event.feeAmount.toStringAsFixed(0)}',
                ),
              if (event.capacity != null)
                _MetaRow(
                  icon: Icons.groups_outlined,
                  label: 'Capacity',
                  value: '${event.capacity}',
                ),
            ],
          ),
        ),
        if (event.description != null && event.description!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const AppSectionHeader(
            title: 'About',
            icon: Icons.notes_rounded,
          ),
          AppCard(
            child: Text(
              event.description!,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

/// One labeled fact line: leading icon · fixed-width label · value.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
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
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: AppType.semibold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status as a single clear control — current state plus a "Change status"
/// menu — instead of a wrapping row of equal transition buttons.
class _StatusSection extends ConsumerWidget {
  const _StatusSection({required this.event});
  final EventEntry event;

  Future<void> _changeTo(WidgetRef ref, EventStatus next) async {
    final repo = await ref.read(eventsRepoProvider.future);
    if (repo == null) return;
    await repo.updateStatus(event.id, next);
    ref
      ..invalidate(eventByIdProvider(event.id))
      ..invalidate(eventsListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Status',
          icon: Icons.flag_outlined,
          trailing: AppBadge(
            text: event.status.label,
            tone: _statusTone(event.status),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: PopupMenuButton<EventStatus>(
            tooltip: 'Change status',
            onSelected: (next) => _changeTo(ref, next),
            itemBuilder: (_) => [
              for (final s in EventStatus.values)
                if (s != event.status)
                  PopupMenuItem(value: s, child: Text(s.label)),
            ],
            child: const ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              leading: Icon(Icons.swap_horiz_outlined),
              title: Text('Change status'),
              trailing: Icon(Icons.expand_more),
            ),
          ),
        ),
      ],
    );
  }
}

class _RegistrationsSection extends ConsumerWidget {
  const _RegistrationsSection({
    required this.event,
    required this.regsAsync,
    required this.canManage,
  });
  final EventEntry event;
  final AsyncValue<List<EventRegistration>> regsAsync;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canAdd = canManage && event.status != EventStatus.cancelled;
    final count = regsAsync.valueOrNull?.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Registrations',
          icon: Icons.groups_2_outlined,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count != null)
                AppBadge(text: '$count', tone: AppBadgeTone.brand),
              if (canAdd) ...[
                const SizedBox(width: AppSpacing.xs),
                TextButton.icon(
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Add'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => EventRegisterSheet(event: event),
                  ),
                ),
              ],
            ],
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: regsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: AppSkeletonList(count: 3),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                friendlyError(e),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            data: (rs) {
              if (rs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: AppEmptyState(
                    icon: Icons.how_to_reg_outlined,
                    title: 'No registrations yet',
                    subtitle: 'Registered students will appear here.',
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rs.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _RegRow(
                      reg: rs[i],
                      eventId: event.id,
                      canManage: canManage,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RegRow extends ConsumerWidget {
  const _RegRow({
    required this.reg,
    required this.eventId,
    required this.canManage,
  });
  final EventRegistration reg;
  final String eventId;
  final bool canManage;

  AppBadgeTone _regTone(String status) {
    switch (status) {
      case 'attended':
        return AppBadgeTone.success;
      case 'cancelled':
        return AppBadgeTone.danger;
      case 'no_show':
        return AppBadgeTone.danger;
      case 'waitlisted':
        return AppBadgeTone.warning;
      case 'registered':
        return AppBadgeTone.info;
    }
    return AppBadgeTone.neutral;
  }

  String _regLabel(String status) => switch (status) {
        'attended' => 'Attended',
        'cancelled' => 'Cancelled',
        'no_show' => 'No show',
        'waitlisted' => 'Waitlisted',
        'registered' => 'Registered',
        _ => status,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final s = students.where((s) => s.id == reg.studentId).firstOrNull;
    final name = s?.fullName ?? reg.studentId.substring(0, 8);
    final df = DateFormat('dd MMM yyyy');
    return AppListTile(
      wrapLeading: false,
      leading: AppAvatar(name, size: 40),
      title: Text(name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppBadge(text: _regLabel(reg.status), tone: _regTone(reg.status)),
            if (reg.feePaid)
              const AppBadge(text: 'Fee paid', tone: AppBadgeTone.success),
            Text(
              'Reg. ${df.format(reg.registeredAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      trailing: canManage
          ? PopupMenuButton<String>(
              tooltip: 'Registration actions',
              onSelected: (v) async {
                final repo = await ref.read(eventsRepoProvider.future);
                if (repo == null) return;
                if (v == 'attended') {
                  await repo.markAttended(reg.id);
                } else if (v == 'cancel') {
                  await repo.cancelRegistration(reg.id);
                }
                ref.invalidate(eventRegistrationsProvider(eventId));
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'attended', child: Text('Mark attended')),
                PopupMenuItem(value: 'cancel', child: Text('Cancel')),
              ],
            )
          : null,
    );
  }
}
