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
      appBar: AppBar(
        title: const Text('Event'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: refresh,
          ),
          if (canManage)
            IconButton(
              icon: const Icon(Icons.emoji_events_outlined),
              tooltip: 'Results & certificates',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EventResultsPage(eventId: eventId),
                ),
              ),
            ),
          if (canManage)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete event',
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: eventAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: refresh,
        ),
        data: (event) {
          if (event == null) {
            return const AppEmptyState(
              icon: Icons.event_busy_outlined,
              title: 'Not found',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _Header(event: event),
              if (canManage) ...[
                const SizedBox(height: AppSpacing.md),
                _StatusSection(event: event),
              ],
              const SizedBox(height: AppSpacing.md),
              _RegistrationsSection(
                event: event,
                regsAsync: regsAsync,
                canManage: canManage,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Hard-delete the event after confirmation. Cascades to its registrations
  /// and results (FK on delete cascade). RLS limits this to admin tier +
  /// center_admin + head_coach, which is exactly the page's [canManage] gate.
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

class _Header extends StatelessWidget {
  const _Header({required this.event});
  final EventEntry event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('EEE, dd MMM yyyy · h:mma');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(event.title, style: theme.textTheme.titleLarge),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppBadge(
                text: event.status.label,
                tone: _statusTone(event.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            event.kind.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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
              value: '₹${event.feeAmount}',
            ),
          if (event.capacity != null)
            _MetaRow(
              icon: Icons.groups_outlined,
              label: 'Capacity',
              value: '${event.capacity}',
            ),
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(event.description!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// One labeled fact line in the header card: icon · label · value.
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
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
            child: Text(value, style: theme.textTheme.bodyMedium),
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
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: AppSectionHeader(
              title: 'Status',
              trailing: AppBadge(
                text: event.status.label,
                tone: _statusTone(event.status),
              ),
            ),
          ),
          PopupMenuButton<EventStatus>(
            tooltip: 'Change status',
            onSelected: (next) => _changeTo(ref, next),
            itemBuilder: (_) => [
              for (final s in EventStatus.values)
                if (s != event.status)
                  PopupMenuItem(value: s, child: Text(s.label)),
            ],
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('Change status'),
              trailing: const Icon(Icons.expand_more),
            ),
          ),
        ],
      ),
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
    final canAdd = canManage && event.status != EventStatus.cancelled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Registrations',
          trailing: canAdd
              ? TextButton.icon(
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Add'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => EventRegisterSheet(event: event),
                  ),
                )
              : null,
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            data: (rs) {
              if (rs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'No registrations yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
    final df = DateFormat('dd MMM yyyy');
    return AppListTile(
      wrapLeading: false,
      leading: CircleAvatar(child: Text(s == null ? '?' : s.firstName[0])),
      title: Text(s?.fullName ?? reg.studentId.substring(0, 8)),
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
