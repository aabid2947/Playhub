import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class AcademiesPage extends ConsumerStatefulWidget {
  const AcademiesPage({super.key});

  @override
  ConsumerState<AcademiesPage> createState() => _AcademiesPageState();
}

class _AcademiesPageState extends ConsumerState<AcademiesPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allAcademiesProvider);
    final df = DateFormat('dd MMM yyyy');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: AppFormField(
            hint: 'Filter by name…',
            prefixIcon: const Icon(Icons.search),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const AppLoading(),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(allAcademiesProvider),
            ),
            data: (rows) {
              final list = _query.isEmpty
                  ? rows
                  : rows.where((a) => a.name.toLowerCase().contains(_query));
              if (list.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.school_outlined,
                  title: 'No academies',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(allAcademiesProvider),
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = list.elementAt(i);
                    return AppListTile(
                      title: Text(a.name),
                      subtitle: Text(
                        [
                          a.subscriptionStatus,
                          if (a.trialEndsAt != null &&
                              a.subscriptionStatus == 'trial')
                            'trial → ${df.format(a.trialEndsAt!)}',
                          'created ${df.format(a.createdAt)}',
                        ].join(' · '),
                      ),
                      trailing: Switch(
                        value: a.isActive,
                        onChanged: (v) async {
                          await ref
                              .read(superAdminRepoProvider)
                              .setAcademyActive(a.id, v);
                          ref.invalidate(allAcademiesProvider);
                        },
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
