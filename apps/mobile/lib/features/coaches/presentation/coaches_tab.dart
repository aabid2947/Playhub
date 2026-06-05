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

class CoachesTab extends ConsumerWidget {
  const CoachesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coachesAsync = ref.watch(coachesProvider);
    final caps = ref.watch(capabilitiesProvider);

    return Scaffold(
      body: Column(
        children: [
          if (caps.manageCoaches)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const CoachBulkImportPage(),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import CSV'),
                ),
              ),
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
                  return const AppEmptyState(
                    icon: Icons.sports_outlined,
                    title: 'No coaches yet',
                    subtitle: 'Tap "New coach" to onboard your first one.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(coachesProvider),
                  child: ListView.separated(
                    itemCount: coaches.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _CoachTile(coach: coaches[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: caps.manageCoaches
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const CoachFormPage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New coach'),
            )
          : null,
    );
  }
}

class _CoachTile extends StatelessWidget {
  const _CoachTile({required this.coach});
  final Coach coach;

  @override
  Widget build(BuildContext context) {
    final initials =
        (coach.firstName.isNotEmpty ? coach.firstName[0] : '?') +
            (coach.lastName.isNotEmpty ? coach.lastName[0] : '');
    final subtitle = [
      if (coach.specialization.isNotEmpty) coach.specialization.first,
      if (coach.experienceYears != null) '${coach.experienceYears} yrs',
      if (coach.phone != null) coach.phone,
    ].whereType<String>().join(' • ');
    return AppListTile(
      leading: AvatarView(url: coach.photo, fallbackInitials: initials),
      wrapLeading: false,
      title: Text(coach.fullName),
      subtitle: Text(subtitle),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => CoachFormPage(existing: coach)),
      ),
    );
  }
}
