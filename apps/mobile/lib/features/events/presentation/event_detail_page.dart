import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/events/presentation/event_register_sheet.dart';
import 'package:playhub/features/events/presentation/event_results_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/core/error_messages.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(eventByIdProvider(eventId));
              ref.invalidate(eventRegistrationsProvider(eventId));
            },
          ),
        ],
      ),
      body: eventAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () {
            ref.invalidate(eventByIdProvider(eventId));
            ref.invalidate(eventRegistrationsProvider(eventId));
          },
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
              const SizedBox(height: AppSpacing.md),
              if (canManage) _ManageBar(event: event),
              const SizedBox(height: AppSpacing.md),
              _RegistrationsSection(
                event: event,
                regsAsync: regsAsync,
                canManage: canManage,
              ),
              const SizedBox(height: AppSpacing.xl),
              if (canManage)
                FilledButton.icon(
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Results & certificates'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EventResultsPage(eventId: eventId),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.event});
  final EventEntry event;

  AppBadgeTone _toneFor(EventStatus s) {
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

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, dd MMM yyyy · h:mma');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('${event.kind.label} · ${df.format(event.startsAt)}'),
          if (event.endsAt != null) Text('Ends: ${df.format(event.endsAt!)}'),
          if (event.location != null && event.location!.isNotEmpty)
            Text('At: ${event.location}'),
          if (event.feeAmount > 0) Text('Fee: ₹${event.feeAmount}'),
          if (event.capacity != null) Text('Capacity: ${event.capacity}'),
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(event.description!),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: AppBadge(
              text: event.status.label,
              tone: _toneFor(event.status),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManageBar extends ConsumerWidget {
  const _ManageBar({required this.event});
  final EventEntry event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Wrap(
        children: [
          for (final s in EventStatus.values)
            if (s != event.status)
              TextButton(
                onPressed: () async {
                  final repo = await ref.read(eventsRepoProvider.future);
                  if (repo == null) return;
                  await repo.updateStatus(event.id, s);
                  ref.invalidate(eventByIdProvider(event.id));
                  ref.invalidate(eventsListProvider);
                },
                child: Text('→ ${s.label}'),
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
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: const Text('Registrations'),
            subtitle: regsAsync.when(
              loading: () => const Text('…'),
              error: (e, _) => Text(friendlyError(e)),
              data: (rs) => Text(
                rs.isEmpty ? 'No registrations yet' : '${rs.length} registered',
              ),
            ),
            trailing: canManage && event.status != EventStatus.cancelled
                ? FilledButton.tonalIcon(
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
          regsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rs) {
              if (rs.isEmpty) return const SizedBox.shrink();
              return Column(
                children: [
                  for (final r in rs)
                    _RegRow(reg: r, eventId: event.id, canManage: canManage),
                ],
              );
            },
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final s = students.where((s) => s.id == reg.studentId).firstOrNull;
    return ListTile(
      leading: CircleAvatar(child: Text(s == null ? '?' : s.firstName[0])),
      title: Text(s?.fullName ?? reg.studentId.substring(0, 8)),
      subtitle: Text(reg.status),
      trailing: canManage
          ? PopupMenuButton<String>(
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
