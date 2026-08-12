import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/features/students/presentation/student_bulk_import_page.dart';
import 'package:playhub/features/students/presentation/student_form_page.dart';
import 'package:playhub/features/subscription/data/trial_limits.dart';
import 'package:playhub/features/subscription/presentation/upgrade_prompt.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class StudentsTab extends ConsumerStatefulWidget {
  const StudentsTab({super.key});

  @override
  ConsumerState<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends ConsumerState<StudentsTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applySearch() {
    ref.read(studentsFilterProvider.notifier).state =
        ref.read(studentsFilterProvider).copyWith(search: _search.text);
  }

  void _openForm({Student? existing}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => StudentFormPage(existing: existing)),
    );
  }

  // Reaching a free-trial cap opens the upgrade prompt (RLS is the hard gate).
  Future<void> _showTrialLimit(String message) =>
      showUpgradePrompt(context, message: message);

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentsProvider);
    final caps = ref.watch(capabilitiesProvider);

    // Free-trial cap: once the academy hits its student limit, the create
    // entry points show an upgrade prompt instead (RLS is the hard backstop).
    final limits = ref.watch(trialLimitsProvider).valueOrNull;
    final studentsBlocked = limits?.studentsReached ?? false;

    // Bulk import creates NEW students — onboarding, so hide it for roles that
    // can't create (e.g. coaches, who only edit their own batch students). RLS
    // rejects it regardless.
    final onImport = !caps.createStudents
        ? null
        : studentsBlocked
            ? () => _showTrialLimit(limits!.studentsMessage)
            : () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const StudentBulkImportPage(),
                  ),
                );

    return Scaffold(
      // Body tab under owner_home_shell's single AppBar — no AppBar here; the
      // in-body header row stands in for it.
      body: Column(
        children: [
          _FilterBar(
            controller: _search,
            onSearch: _applySearch,
            count: studentsAsync.valueOrNull?.length,
            onImport: onImport,
          ),
          Expanded(
            child: studentsAsync.when(
              loading: () => const AppSkeletonList(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(studentsProvider),
              ),
              data: (students) {
                if (students.isEmpty) {
                  return const _EmptyState();
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(studentsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      // Leave room so the last tile clears the FAB.
                      AppSpacing.xxl + AppSpacing.xl,
                    ),
                    itemCount: students.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _StudentTile(
                      student: students[i],
                      onTap: () => _openForm(existing: students[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: caps.createStudents
          ? FloatingActionButton.extended(
              heroTag: 'fab-students',
              onPressed: studentsBlocked
                  ? () => _showTrialLimit(limits!.studentsMessage)
                  : _openForm,
              icon: Icon(
                studentsBlocked ? Icons.lock_outline : Icons.person_add,
              ),
              label: const Text('New student'),
            )
          : null,
    );
  }
}

/// The in-body list header: a navy title with a live count badge (the tab has
/// no AppBar), the search field with an inline status filter + CSV import, and
/// the sport chip bar — one coherent surface so the filters never read as
/// orphaned controls.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.controller,
    required this.onSearch,
    required this.count,
    required this.onImport,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;

  /// Live result count for the header badge; null while loading.
  final int? count;

  // Null hides the CSV-import action (roles that can't create students).
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filter = ref.watch(studentsFilterProvider);

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + live count.
                Row(
                  children: [
                    Text('Students', style: theme.textTheme.headlineSmall),
                    const SizedBox(width: AppSpacing.sm),
                    if (count != null)
                      AppBadge(
                        text: count == 1 ? '1 total' : '$count total',
                        tone: AppBadgeTone.brand,
                      ),
                    const Spacer(),
                    if (onImport != null)
                      IconButton(
                        tooltip: 'Import CSV',
                        icon: const Icon(Icons.upload_file_outlined),
                        onPressed: onImport,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Search with an inline status filter.
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        onSubmitted: (_) => onSearch(),
                        decoration: InputDecoration(
                          hintText: 'Search name, parent…',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    controller.clear();
                                    onSearch();
                                  },
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    PopupMenuButton<String?>(
                      tooltip: 'Filter status',
                      icon: Icon(
                        Icons.filter_list,
                        color: filter.status == null
                            ? scheme.onSurfaceVariant
                            : scheme.primary,
                      ),
                      initialValue: filter.status,
                      onSelected: (v) {
                        ref.read(studentsFilterProvider.notifier).state =
                            filter.copyWith(status: v);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem<String?>(child: Text('All')),
                        PopupMenuItem(value: 'pending', child: Text('Pending')),
                        PopupMenuItem(value: 'active', child: Text('Active')),
                        PopupMenuItem(value: 'paused', child: Text('Paused')),
                        PopupMenuItem(
                          value: 'inactive',
                          child: Text('Inactive'),
                        ),
                        PopupMenuItem(
                          value: 'graduated',
                          child: Text('Graduated'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          SportFilterChipBar(
            selectedId: filter.sportId,
            onSelected: (id) {
              ref.read(studentsFilterProvider.notifier).state = id == null
                  ? filter.copyWith(clearSport: true)
                  : filter.copyWith(sportId: id);
            },
          ),
        ],
      ),
    );
  }
}

/// A people-list row in the v1 list archetype: a card with a gradient (or
/// photo) avatar → name + sport·parent subtitle → trailing status badges.
class _StudentTile extends ConsumerWidget {
  const _StudentTile({required this.student, required this.onTap});
  final Student student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final initials =
        (student.firstName.isNotEmpty ? student.firstName[0] : '?') +
            (student.lastName.isNotEmpty ? student.lastName[0] : '');
    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: student.sportId)),
    );
    final hasSport = sportLabel != '—';
    final sportColor = colorFromName(sportLabel);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          // Photo when set, otherwise the deterministic gradient-initials disc.
          if (student.photo != null && student.photo!.isNotEmpty)
            AvatarView(
              url: student.photo,
              fallbackInitials: initials,
              radius: 24,
            )
          else
            AppAvatar(student.fullName, size: 48),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Two facts that matter on a people list: sport (with its
                // colored glyph) and the parent it maps to. Skill level lives
                // on the detail page so the subtitle stays one tight line.
                Row(
                  children: [
                    if (hasSport) ...[
                      Icon(
                        sportIcon(sportLabel),
                        size: 14,
                        color: sportColor,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        hasSport
                            ? '$sportLabel · ${student.parentName}'
                            : 'Parent: ${student.parentName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusBadge(status: student.status),
              if (student.feeOverdue) ...[
                const SizedBox(height: 6),
                const AppBadge(text: 'Unpaid', tone: AppBadgeTone.danger),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      'active' => AppBadgeTone.success,
      // Awaiting a first payment — not a problem, but not active either.
      'pending' => AppBadgeTone.warning,
      'paused' => AppBadgeTone.warning,
      'inactive' => AppBadgeTone.neutral,
      'graduated' => AppBadgeTone.info,
      _ => AppBadgeTone.neutral,
    };
    return AppBadge(text: status, tone: tone);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.group_outlined,
      title: 'No students yet',
      subtitle: 'Tap "New student" to enroll your first one.',
    );
  }
}
