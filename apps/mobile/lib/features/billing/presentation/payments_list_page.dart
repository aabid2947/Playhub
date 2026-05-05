import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/billing/data/payment.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';

final _allPaymentsProvider =
    FutureProvider<List<Payment>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('payments')
      .select()
      .eq('academy_id', academyId)
      .order('paid_at', ascending: false)
      .limit(200);
  return (rows as List)
      .map((r) => Payment.fromMap(r as Map<String, dynamic>))
      .toList();
});

class PaymentsListPage extends ConsumerWidget {
  const PaymentsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(_allPaymentsProvider);
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final byId = {for (final s in students) s.id: s};

    return paymentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (payments) {
        if (payments.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No payments recorded yet.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_allPaymentsProvider),
          child: ListView.separated(
            itemCount: payments.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = payments[i];
              return ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(
                  byId[p.studentId]?.fullName ?? '(unknown)',
                ),
                subtitle: Text(
                  '${p.method.label} · ${p.paidAt.toIso8601String().substring(0, 10)}'
                  ' · ${p.status}',
                ),
                trailing: Text(
                  '₹${p.amount.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
