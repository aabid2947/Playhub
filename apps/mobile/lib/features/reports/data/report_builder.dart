import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

/// What entity is being reported on.
enum ReportEntity {
  students('students', 'Students'),
  invoices('invoices', 'Invoices'),
  payments('payments', 'Payments'),
  attendance('attendance_records', 'Attendance'),
  leads('leads', 'Leads'),
  events('events', 'Events');

  const ReportEntity(this.table, this.label);
  final String table;
  final String label;

  /// Columns the user can pick / filter / group by per entity. The first
  /// item is shown as default in the column dropdown.
  List<ReportColumn> get columns => switch (this) {
        ReportEntity.students => const [
            ReportColumn('id', 'ID'),
            ReportColumn('first_name', 'First name'),
            ReportColumn('last_name', 'Last name'),
            ReportColumn('parent_name', 'Parent name'),
            ReportColumn('phone', 'Phone'),
            ReportColumn('center_id', 'Center'),
            ReportColumn('status', 'Status'),
            ReportColumn('sport', 'Sport'),
            ReportColumn('skill_level', 'Skill'),
            ReportColumn('created_at', 'Created'),
          ],
        ReportEntity.invoices => const [
            ReportColumn('id', 'ID'),
            ReportColumn('invoice_number', 'Invoice #'),
            ReportColumn('student_id', 'Student'),
            ReportColumn('status', 'Status'),
            ReportColumn('issued_at', 'Issued'),
            ReportColumn('due_date', 'Due date'),
            ReportColumn('amount', 'Amount'),
            ReportColumn('amount_paid', 'Paid'),
          ],
        ReportEntity.payments => const [
            ReportColumn('id', 'ID'),
            ReportColumn('invoice_id', 'Invoice'),
            ReportColumn('amount', 'Amount'),
            ReportColumn('method', 'Method'),
            ReportColumn('paid_at', 'Paid at'),
          ],
        ReportEntity.attendance => const [
            ReportColumn('id', 'ID'),
            ReportColumn('student_id', 'Student'),
            ReportColumn('batch_id', 'Batch'),
            ReportColumn('date', 'Date'),
            ReportColumn('status', 'Status'),
          ],
        ReportEntity.leads => const [
            ReportColumn('id', 'ID'),
            ReportColumn('first_name', 'First name'),
            ReportColumn('phone', 'Phone'),
            ReportColumn('status', 'Status'),
            ReportColumn('source', 'Source'),
            ReportColumn('created_at', 'Created'),
          ],
        ReportEntity.events => const [
            ReportColumn('id', 'ID'),
            ReportColumn('title', 'Title'),
            ReportColumn('kind', 'Kind'),
            ReportColumn('status', 'Status'),
            ReportColumn('starts_at', 'Starts'),
            ReportColumn('fee_amount', 'Fee'),
          ],
      };
}

class ReportColumn {
  const ReportColumn(this.dbName, this.label);
  final String dbName;
  final String label;
}

class ReportFilter {
  const ReportFilter({
    required this.column,
    required this.op,
    required this.value,
  });
  final String column;
  final String op; // 'eq' | 'neq' | 'gt' | 'gte' | 'lt' | 'lte' | 'ilike'
  final String value;
}

class ReportSpec {
  const ReportSpec({
    required this.entity,
    required this.columns,
    this.filters = const [],
    this.groupBy,
    this.orderBy,
    this.descending = false,
    this.limit = 200,
  });

  final ReportEntity entity;
  final List<String> columns;
  final List<ReportFilter> filters;
  final String? groupBy;
  final String? orderBy;
  final bool descending;
  final int limit;
}

/// Runs the [ReportSpec]. RLS still applies — academy_id is added as an
/// implicit filter so a user can never escape their own tenant.
final reportRunnerProvider =
    FutureProvider.family<List<Map<String, dynamic>>, ReportSpec>(
        (ref, spec) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];

  final cols = spec.columns.isEmpty ? '*' : spec.columns.join(',');
  var query =
      client.from(spec.entity.table).select(cols).eq('academy_id', profile!.academyId!);

  for (final f in spec.filters) {
    final v = f.value.trim();
    if (v.isEmpty) continue;
    query = switch (f.op) {
      'eq' => query.eq(f.column, v),
      'neq' => query.neq(f.column, v),
      'gt' => query.gt(f.column, v),
      'gte' => query.gte(f.column, v),
      'lt' => query.lt(f.column, v),
      'lte' => query.lte(f.column, v),
      'ilike' => query.ilike(f.column, '%$v%'),
      _ => query,
    };
  }

  final orderCol = spec.orderBy ?? spec.columns.firstOrNull;
  final ordered = orderCol == null
      ? query.limit(spec.limit)
      : query.order(orderCol, ascending: !spec.descending).limit(spec.limit);

  final rows = await ordered;
  final list = (rows as List).cast<Map<String, dynamic>>();

  if (spec.groupBy == null) return list;

  // Client-side group-by: emit { <key>: ..., count: <n> } rows.
  final grouped = <String, int>{};
  for (final r in list) {
    final k = r[spec.groupBy] == null ? '(null)' : r[spec.groupBy].toString();
    grouped[k] = (grouped[k] ?? 0) + 1;
  }
  return grouped.entries
      .map((e) => {spec.groupBy!: e.key, 'count': e.value})
      .toList(growable: false);
});
