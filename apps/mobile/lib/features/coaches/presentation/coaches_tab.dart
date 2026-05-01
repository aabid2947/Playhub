import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/coaches/presentation/coach_bulk_import_page.dart';
import 'package:playhub/features/coaches/presentation/coach_form_page.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';

class CoachesTab extends ConsumerWidget {
  const CoachesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coachesAsync = ref.watch(coachesProvider);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: SizedBox.shrink(
          child: Material(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Import CSV',
                    icon: const Icon(Icons.upload_file_outlined),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const CoachBulkImportPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: coachesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (coaches) {
          if (coaches.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(coachesProvider),
            child: ListView.separated(
              itemCount: coaches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _CoachTile(coach: coaches[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const CoachFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New coach'),
      ),
    );
  }
}

class _CoachTile extends StatelessWidget {
  const _CoachTile({required this.coach});
  final Coach coach;

  @override
  Widget build(BuildContext context) {
    final initials = (coach.firstName.isNotEmpty
            ? coach.firstName[0]
            : '?') +
        (coach.lastName.isNotEmpty ? coach.lastName[0] : '');
    final subtitle = [
      if (coach.specialization.isNotEmpty) coach.specialization.first,
      if (coach.experienceYears != null) '${coach.experienceYears} yrs',
      if (coach.phone != null) coach.phone,
    ].whereType<String>().join(' • ');
    return ListTile(
      leading: AvatarView(url: coach.photo, fallbackInitials: initials),
      title: Text(coach.fullName),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CoachFormPage(existing: coach),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No coaches yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "New coach" to onboard your first one.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
