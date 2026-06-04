import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/features/students/presentation/student_bulk_import_page.dart';
import 'package:playhub/features/students/presentation/student_form_page.dart';
import 'package:playhub/core/error_messages.dart';
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
    ref.read(studentsFilterProvider.notifier).state = ref
        .read(studentsFilterProvider)
        .copyWith(search: _search.text);
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentsProvider);
    final filter = ref.watch(studentsFilterProvider);
    final caps = ref.watch(capabilitiesProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onSubmitted: (_) => _applySearch(),
                    decoration: InputDecoration(
                      hintText: 'Search name, parent…',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                _applySearch();
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String?>(
                  tooltip: 'Filter status',
                  icon: const Icon(Icons.filter_list),
                  initialValue: filter.status,
                  onSelected: (v) {
                    ref.read(studentsFilterProvider.notifier).state = filter
                        .copyWith(status: v);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String?>(child: Text('All')),
                    PopupMenuItem(value: 'active', child: Text('Active')),
                    PopupMenuItem(value: 'paused', child: Text('Paused')),
                    PopupMenuItem(value: 'inactive', child: Text('Inactive')),
                    PopupMenuItem(value: 'graduated', child: Text('Graduated')),
                  ],
                ),
                IconButton(
                  tooltip: 'Import CSV',
                  icon: const Icon(Icons.upload_file_outlined),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const StudentBulkImportPage(),
                    ),
                  ),
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
          Expanded(
            child: studentsAsync.when(
              loading: () => const AppLoading(),
              error: (e, _) => AppErrorView(message: friendlyError(e)),
              data: (students) {
                if (students.isEmpty) {
                  return const _EmptyState();
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(studentsProvider),
                  child: ListView.separated(
                    itemCount: students.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _StudentTile(student: students[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: caps.manageStudents
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const StudentFormPage()),
              ),
              icon: const Icon(Icons.person_add),
              label: const Text('New student'),
            )
          : null,
    );
  }
}

class _StudentTile extends ConsumerWidget {
  const _StudentTile({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials =
        (student.firstName.isNotEmpty ? student.firstName[0] : '?') +
        (student.lastName.isNotEmpty ? student.lastName[0] : '');
    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: student.sportId)),
    );
    return ListTile(
      leading: AvatarView(url: student.photo, fallbackInitials: initials),
      title: Text(student.fullName),
      subtitle: Text(
        [
          if (sportLabel != '—') sportLabel,
          if (student.skillLevel != null) student.skillLevel!,
          'parent: ${student.parentName}',
        ].join(' • '),
      ),
      trailing: _StatusBadge(status: student.status),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => StudentFormPage(existing: student)),
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
