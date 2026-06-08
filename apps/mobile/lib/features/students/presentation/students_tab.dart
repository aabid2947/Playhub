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

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentsProvider);
    final caps = ref.watch(capabilitiesProvider);

    return Scaffold(
      body: Column(
        children: [
          _FilterBar(
            controller: _search,
            onSearch: _applySearch,
            // Bulk import creates NEW students — onboarding, so hide it for
            // roles that can't create (e.g. coaches, who only edit their own
            // batch students). RLS rejects it regardless.
            onImport: caps.createStudents
                ? () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const StudentBulkImportPage(),
                      ),
                    )
                : null,
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
                    itemCount: students.length + 1,
                    separatorBuilder: (_, i) =>
                        i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _ResultCount(count: students.length);
                      }
                      return _StudentTile(
                        student: students[i - 1],
                        onTap: () => _openForm(existing: students[i - 1]),
                      );
                    },
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
              onPressed: _openForm,
              icon: const Icon(Icons.person_add),
              label: const Text('New student'),
            )
          : null,
    );
  }
}

/// The single, unified filter block: a search field with an inline status
/// menu, then the sport chip bar in the same coherent surface so the two
/// filters never read as orphaned controls.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.controller,
    required this.onSearch,
    required this.onImport,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;
  // Null hides the CSV-import action (roles that can't create students).
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(studentsFilterProvider);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
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
                    PopupMenuItem(value: 'active', child: Text('Active')),
                    PopupMenuItem(value: 'paused', child: Text('Paused')),
                    PopupMenuItem(value: 'inactive', child: Text('Inactive')),
                    PopupMenuItem(value: 'graduated', child: Text('Graduated')),
                  ],
                ),
                if (onImport != null)
                  IconButton(
                    tooltip: 'Import CSV',
                    icon: const Icon(Icons.upload_file_outlined),
                    onPressed: onImport,
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

/// Visible result count above the list, e.g. "12 students".
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        count == 1 ? '1 student' : '$count students',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StudentTile extends ConsumerWidget {
  const _StudentTile({required this.student, required this.onTap});
  final Student student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials =
        (student.firstName.isNotEmpty ? student.firstName[0] : '?') +
            (student.lastName.isNotEmpty ? student.lastName[0] : '');
    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: student.sportId)),
    );
    // Two facts that matter on a people list: sport and the parent it maps to.
    // Skill level lives on the detail page so the subtitle stays one tight line.
    final facts = <String>[
      if (sportLabel != '—') sportLabel,
      'Parent: ${student.parentName}',
    ];
    return AppListTile(
      wrapLeading: false,
      leading: AvatarView(url: student.photo, fallbackInitials: initials),
      title: Text(student.fullName),
      subtitle: Text(
        facts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (student.feeOverdue) ...[
            const AppBadge(text: 'Unpaid', tone: AppBadgeTone.danger),
            const SizedBox(width: AppSpacing.xs),
          ],
          _StatusBadge(status: student.status),
        ],
      ),
      onTap: onTap,
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
