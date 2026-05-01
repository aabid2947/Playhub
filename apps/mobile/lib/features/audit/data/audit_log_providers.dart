import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/audit/data/audit_log.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

const _pageSize = 50;

/// Most-recent first. Embeds the user's display name via FK join so we
/// don't need a second round-trip.
final auditLogsProvider = FutureProvider<List<AuditLog>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];

  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('audit_logs')
      .select('*, users:user_id(first_name, last_name)')
      .eq('academy_id', academyId)
      .order('created_at', ascending: false)
      .limit(_pageSize);
  return (rows as List)
      .map((r) => AuditLog.fromMap(r as Map<String, dynamic>))
      .toList();
});
