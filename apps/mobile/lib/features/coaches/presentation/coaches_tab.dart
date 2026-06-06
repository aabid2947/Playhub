import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/coaches/presentation/coach_bulk_import_page.dart';
import 'package:playhub/features/coaches/presentation/coach_form_page.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Local active/inactive filter for the coaches list. `null` = all.
enum _CoachStatusFilter { all, active, inactive }

class CoachesTab extends ConsumerStatefulWidget {
  const CoachesTab({super.key});

  @override
  ConsumerState<CoachesTab> createState() => _CoachesTabState();
}

class _CoachesTabState extends ConsumerState<CoachesTab> {
  final _search = TextEditingController();
  _CoachStatusFilter _status = _CoachStatusFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openForm({Coach? existing}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CoachFormPage(existing: existing)),
    );
  }

  void _openImport() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CoachBulkImportPage()),
    );
  }

  /// Client-side search + status filter over the already-fetched list. The
  /// coaches provider returns the full tenant-scoped set; we narrow it here so
  /// the data layer stays untouched.
  List<Coach> _filter(List<Coach> coaches) {
    final query = _search.text.trim().toLowerCase();
    return coaches.where((c) {
      switch (_status) {
        case _CoachStatusFilter.active:
          if (!c.isActive) return false;
        case _CoachStatusFilter.inactive:
          if (c.isActive) return false;
        case _CoachStatusFilter.all:
          break;
      }
      if (query.isEmpty) return true;
      final haystack = [
        c.fullName,
        ...c.specialization,
        if (c.email != null) c.email!,
        if (c.phone != null) c.phone!,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final coachesAsync = ref.watch(coachesProvider);
    final caps = ref.watch(capabilitiesProvider);

    return Scaffold(
      body: Column(
        children: [
          _FilterBar(
            controller: _search,
            status: _status,
            onSearch: () => setState(() {}),
            onStatusChanged: (v) => setState(() => _status = v),
            onImport: caps.manageCoaches ? _openImport : null,
          ),
          Expanded(
            child: coachesAsync.when(
              loading: () => const AppSkeletonList(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(coachesProvider),
              ),
              data: (coaches) {
                if (coaches.isEmpty) {
                  return const _EmptyState();
                }
                final results = _filter(coaches);
                if (results.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No matches',
                    subtitle: 'Try a different name or clear the filters.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(coachesProvider),
                  child: ListView.separated(
                    itemCount: results.length + 1,
                    separatorBuilder: (_, i) => i == 0
                        ? const SizedBox.shrink()
                        : const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _ResultCount(count: results.length);
                      }
                      return _CoachTile(
                        coach: results[i - 1],
                        onTap: () => _openForm(existing: results[i - 1]),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: caps.manageCoaches
          ? FloatingActionButton.extended(
              heroTag: 'fab-coaches',
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('New coach'),
            )
          : null,
    );
  }
}

/// The single, unified filter block: a search field with an inline status
/// menu and the secondary CSV-import action, so the list's controls read as
/// one coherent surface rather than orphaned buttons.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.status,
    required this.onSearch,
    required this.onStatusChanged,
    required this.onImport,
  });

  final TextEditingController controller;
  final _CoachStatusFilter status;
  final VoidCallback onSearch;
  final ValueChanged<_CoachStatusFilter> onStatusChanged;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: Padding(
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
                onChanged: (_) => onSearch(),
                decoration: InputDecoration(
                  hintText: 'Search name, specialization…',
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
            PopupMenuButton<_CoachStatusFilter>(
              tooltip: 'Filter status',
              icon: Icon(
                Icons.filter_list,
                color: status == _CoachStatusFilter.all
                    ? scheme.onSurfaceVariant
                    : scheme.primary,
              ),
              initialValue: status,
              onSelected: onStatusChanged,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _CoachStatusFilter.all,
                  child: Text('All'),
                ),
                PopupMenuItem(
                  value: _CoachStatusFilter.active,
                  child: Text('Active'),
                ),
                PopupMenuItem(
                  value: _CoachStatusFilter.inactive,
                  child: Text('Inactive'),
                ),
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
    );
  }
}

/// Visible result count above the list, e.g. "12 coaches".
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
        count == 1 ? '1 coach' : '$count coaches',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CoachTile extends StatelessWidget {
  const _CoachTile({required this.coach, required this.onTap});
  final Coach coach;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initials =
        (coach.firstName.isNotEmpty ? coach.firstName[0] : '?') +
            (coach.lastName.isNotEmpty ? coach.lastName[0] : '');
    // Two facts that matter on a people list: what they coach and how senior.
    // Phone/email live on the detail page so the subtitle stays one tight line.
    final facts = <String>[
      if (coach.specialization.isNotEmpty) coach.specialization.first,
      if (coach.experienceYears != null) '${coach.experienceYears} yrs',
    ];
    return AppListTile(
      wrapLeading: false,
      leading: AvatarView(url: coach.photo, fallbackInitials: initials),
      title: Text(coach.fullName),
      subtitle: Text(
        facts.isEmpty ? 'Coach' : facts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _StatusBadge(isActive: coach.isActive),
      onTap: onTap,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      text: isActive ? 'Active' : 'Inactive',
      tone: isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.sports_outlined,
      title: 'No coaches yet',
      subtitle: 'Tap "New coach" to onboard your first one.',
    );
  }
}
