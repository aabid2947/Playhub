import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AcademyRow {
  const AcademyRow({
    required this.id,
    required this.name,
    required this.subscriptionStatus,
    required this.isActive,
    this.ownerId,
    this.trialEndsAt,
    this.email,
    this.phone,
    required this.createdAt,
  });

  factory AcademyRow.fromMap(Map<String, dynamic> m) => AcademyRow(
        id: m['id'] as String,
        name: m['name'] as String,
        subscriptionStatus: m['subscription_status'] as String,
        isActive: m['is_active'] as bool? ?? true,
        ownerId: m['owner_id'] as String?,
        trialEndsAt: m['trial_ends_at'] == null
            ? null
            : DateTime.parse(m['trial_ends_at'] as String).toLocal(),
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );

  final String id;
  final String name;
  final String subscriptionStatus;
  final bool isActive;
  final String? ownerId;
  final DateTime? trialEndsAt;
  final String? email;
  final String? phone;
  final DateTime createdAt;
}

class PlanRow {
  const PlanRow({
    required this.id,
    required this.code,
    required this.name,
    required this.monthlyPrice,
    required this.isActive,
    this.description,
    this.yearlyPrice,
    this.maxStudents,
    this.maxCoaches,
    this.maxCenters,
  });

  factory PlanRow.fromMap(Map<String, dynamic> m) => PlanRow(
        id: m['id'] as String,
        code: m['code'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        monthlyPrice: (m['monthly_price'] as num).toDouble(),
        yearlyPrice: (m['yearly_price'] as num?)?.toDouble(),
        maxStudents: m['max_students'] as int?,
        maxCoaches: m['max_coaches'] as int?,
        maxCenters: m['max_centers'] as int?,
        isActive: m['is_active'] as bool? ?? true,
      );

  final String id;
  final String code;
  final String name;
  final String? description;
  final double monthlyPrice;
  final double? yearlyPrice;
  final int? maxStudents;
  final int? maxCoaches;
  final int? maxCenters;
  final bool isActive;
}

class SupportTicketRow {
  const SupportTicketRow({
    required this.id,
    required this.academyId,
    required this.subject,
    required this.body,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.category,
    this.assignedTo,
  });

  factory SupportTicketRow.fromMap(Map<String, dynamic> m) =>
      SupportTicketRow(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        subject: m['subject'] as String,
        body: m['body'] as String,
        category: m['category'] as String?,
        priority: m['priority'] as String,
        status: m['status'] as String,
        assignedTo: m['assigned_to'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );

  final String id;
  final String academyId;
  final String subject;
  final String body;
  final String? category;
  final String priority;
  final String status;
  final String? assignedTo;
  final DateTime createdAt;
}

class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.body,
    required this.isStaff,
    required this.createdAt,
    this.authorId,
  });

  factory TicketMessage.fromMap(Map<String, dynamic> m) => TicketMessage(
        id: m['id'] as String,
        body: m['body'] as String,
        isStaff: m['is_staff'] as bool? ?? false,
        authorId: m['author_id'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );

  final String id;
  final String body;
  final bool isStaff;
  final String? authorId;
  final DateTime createdAt;
}

final allAcademiesProvider = FutureProvider<List<AcademyRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('academies')
      .select()
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => AcademyRow.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final globalKpiProvider = FutureProvider<GlobalKpi>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final acads = ref.watch(allAcademiesProvider).valueOrNull ?? const [];

  final activeCount = acads.where((a) => a.isActive).length;
  final trial = acads.where((a) => a.subscriptionStatus == 'trial').length;
  final paying = acads.where((a) => a.subscriptionStatus == 'active').length;
  final pastDue = acads.where((a) => a.subscriptionStatus == 'past_due').length;
  final suspended =
      acads.where((a) => a.subscriptionStatus == 'suspended').length;

  // Sum saas_payments amount as a quick global revenue figure.
  final paymentsSum = await client
      .from('saas_payments')
      .select('amount')
      .limit(10000);
  final totalRevenue = (paymentsSum as List).fold<double>(
      0, (acc, r) => acc + ((r as Map)['amount'] as num).toDouble());

  final outstanding = await client
      .from('saas_invoices')
      .select('amount, amount_paid, tax_amount, status')
      .inFilter('status', ['issued', 'past_due']);
  final outstandingAmount = (outstanding as List).fold<double>(0, (acc, r) {
    final m = r as Map;
    return acc +
        ((m['amount'] as num).toDouble() +
            (m['tax_amount'] as num).toDouble() -
            (m['amount_paid'] as num).toDouble());
  });

  // Open tickets across the platform (open + in_progress + waiting_on_user),
  // mirroring the web console's health KPI.
  final openTix = await client
      .from('support_tickets')
      .select('id')
      .inFilter('status', ['open', 'in_progress', 'waiting_on_user']);
  final openTickets = (openTix as List).length;

  return GlobalKpi(
    academiesActive: activeCount,
    academiesTrial: trial,
    academiesPaying: paying,
    academiesPastDue: pastDue,
    academiesSuspended: suspended,
    totalRevenue: totalRevenue,
    outstandingAmount: outstandingAmount,
    openTickets: openTickets,
  );
});

class GlobalKpi {
  const GlobalKpi({
    required this.academiesActive,
    required this.academiesTrial,
    required this.academiesPaying,
    required this.academiesPastDue,
    required this.academiesSuspended,
    required this.totalRevenue,
    required this.outstandingAmount,
    required this.openTickets,
  });

  final int academiesActive;
  final int academiesTrial;
  final int academiesPaying;
  final int academiesPastDue;
  final int academiesSuspended;
  final double totalRevenue;
  final double outstandingAmount;
  final int openTickets;
}

final allPlansProvider = FutureProvider<List<PlanRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows =
      await client.from('subscription_plans').select().order('monthly_price');
  return (rows as List)
      .map((r) => PlanRow.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final allTicketsProvider = FutureProvider<List<SupportTicketRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('support_tickets')
      .select()
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => SupportTicketRow.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final ticketMessagesProvider =
    FutureProvider.family<List<TicketMessage>, String>((ref, ticketId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('support_ticket_messages')
      .select()
      .eq('ticket_id', ticketId)
      .order('created_at');
  return (rows as List)
      .map((r) => TicketMessage.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

class SuperAdminRepo {
  SuperAdminRepo(this._client);
  final SupabaseClient _client;

  Future<PlanRow> upsertPlan({
    String? id,
    required String code,
    required String name,
    String? description,
    required double monthlyPrice,
    double? yearlyPrice,
    int? maxStudents,
    int? maxCoaches,
    int? maxCenters,
    bool isActive = true,
  }) async {
    final payload = {
      'code': code,
      'name': name,
      'description': description,
      'monthly_price': monthlyPrice,
      'yearly_price': yearlyPrice,
      'max_students': maxStudents,
      'max_coaches': maxCoaches,
      'max_centers': maxCenters,
      'is_active': isActive,
    };
    final r = id == null
        ? await _client
            .from('subscription_plans')
            .insert(payload)
            .select()
            .single()
        : await _client
            .from('subscription_plans')
            .update(payload)
            .eq('id', id)
            .select()
            .single();
    return PlanRow.fromMap(r);
  }

  Future<void> deletePlan(String id) =>
      _client.from('subscription_plans').delete().eq('id', id);

  Future<void> setAcademyActive(String academyId, bool active) =>
      _client
          .from('academies')
          .update({'is_active': active})
          .eq('id', academyId);

  /// Manually record a SaaS payment against an invoice. The apply_saas_payment
  /// trigger bumps amount_paid and flips the invoice to 'paid' when covered.
  /// [method] is one of: razorpay | bank_transfer | manual | free.
  Future<void> recordSaasPayment({
    required String invoiceId,
    required String academyId,
    required double amount,
    required String method,
    String? reference,
  }) async {
    final ref = reference?.trim();
    await _client.from('saas_payments').insert({
      'saas_invoice_id': invoiceId,
      'academy_id': academyId,
      'amount': amount,
      'method': method,
      'reference': (ref == null || ref.isEmpty) ? null : ref,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> updateTicket(
    String ticketId, {
    String? status,
    String? priority,
    String? assignedTo,
  }) async {
    final payload = <String, dynamic>{
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (assignedTo != null) 'assigned_to': assignedTo,
      if (status == 'resolved')
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      if (status == 'closed')
        'closed_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _client.from('support_tickets').update(payload).eq('id', ticketId);
  }

  /// Set (or clear, with null) the ticket's assignee. Separate from
  /// [updateTicket] because that one skips a null assigned_to (can't unassign).
  Future<void> setTicketAssignee(String ticketId, String? userId) async {
    await _client
        .from('support_tickets')
        .update({'assigned_to': userId})
        .eq('id', ticketId);
  }

  Future<void> postStaffReply({
    required String ticketId,
    required String academyId,
    required String body,
  }) async {
    await _client.from('support_ticket_messages').insert({
      'ticket_id': ticketId,
      'academy_id': academyId,
      'is_staff': true,
      'body': body,
    });
  }
}

final superAdminRepoProvider = Provider<SuperAdminRepo>((ref) {
  return SuperAdminRepo(ref.watch(supabaseClientProvider));
});

// ============================================================================
// Academy detail (drill-down): owner + member/student counts + contact, plus
// the academy's SaaS invoices. Cross-tenant reads ride the super-admin RLS.
// ============================================================================

class AcademyDetail {
  const AcademyDetail({
    required this.id,
    required this.name,
    required this.subscriptionStatus,
    required this.isActive,
    required this.createdAt,
    required this.memberCount,
    required this.studentCount,
    this.trialEndsAt,
    this.email,
    this.phone,
    this.city,
    this.state,
    this.ownerName,
    this.ownerEmail,
  });

  final String id;
  final String name;
  final String subscriptionStatus;
  final bool isActive;
  final DateTime createdAt;
  final int memberCount;
  final int studentCount;
  final DateTime? trialEndsAt;
  final String? email;
  final String? phone;
  final String? city;
  final String? state;
  final String? ownerName;
  final String? ownerEmail;

  String? get location {
    final parts = [city, state].where((p) => p != null && p.trim().isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }
}

final academyDetailProvider =
    FutureProvider.family<AcademyDetail, String>((ref, id) async {
  final client = ref.watch(supabaseClientProvider);
  final a = await client
      .from('academies')
      .select('id, name, subscription_status, is_active, email, phone, '
          'city, state, trial_ends_at, created_at, owner_id')
      .eq('id', id)
      .single();
  final m = a;
  final ownerId = m['owner_id'] as String?;

  // Counts (fetch ids, count length — matches the existing stats idiom).
  final members = await client.from('users').select('id').eq('academy_id', id);
  final students =
      await client.from('students').select('id').eq('academy_id', id);

  String? ownerName;
  String? ownerEmail;
  if (ownerId != null) {
    final o = await client
        .from('users')
        .select('first_name, last_name, email')
        .eq('id', ownerId)
        .maybeSingle();
    if (o != null) {
      final full =
          '${(o['first_name'] as String?) ?? ''} ${(o['last_name'] as String?) ?? ''}'
              .trim();
      ownerName = full.isEmpty ? null : full;
      ownerEmail = o['email'] as String?;
    }
  }

  return AcademyDetail(
    id: m['id'] as String,
    name: m['name'] as String,
    subscriptionStatus: m['subscription_status'] as String,
    isActive: m['is_active'] as bool? ?? true,
    email: m['email'] as String?,
    phone: m['phone'] as String?,
    city: m['city'] as String?,
    state: m['state'] as String?,
    trialEndsAt: m['trial_ends_at'] == null
        ? null
        : DateTime.parse(m['trial_ends_at'] as String).toLocal(),
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    ownerName: ownerName,
    ownerEmail: ownerEmail,
    memberCount: (members as List).length,
    studentCount: (students as List).length,
  );
});

class SaasInvoiceRow {
  const SaasInvoiceRow({
    required this.id,
    required this.invoiceNumber,
    required this.status,
    required this.amount,
    required this.taxAmount,
    required this.totalAmount,
    required this.amountPaid,
    this.dueDate,
    this.issuedAt,
  });

  factory SaasInvoiceRow.fromMap(Map<String, dynamic> m) {
    final amount = (m['amount'] as num).toDouble();
    final tax = (m['tax_amount'] as num?)?.toDouble() ?? 0;
    final total = (m['total_amount'] as num?)?.toDouble() ?? (amount + tax);
    return SaasInvoiceRow(
      id: m['id'] as String,
      invoiceNumber: m['invoice_number'] as String,
      status: m['status'] as String,
      amount: amount,
      taxAmount: tax,
      totalAmount: total,
      amountPaid: (m['amount_paid'] as num?)?.toDouble() ?? 0,
      dueDate: m['due_date'] == null
          ? null
          : DateTime.parse(m['due_date'] as String).toLocal(),
      issuedAt: m['issued_at'] == null
          ? null
          : DateTime.parse(m['issued_at'] as String).toLocal(),
    );
  }

  final String id;
  final String invoiceNumber;
  final String status;
  final double amount;
  final double taxAmount;
  final double totalAmount;
  final double amountPaid;
  final DateTime? dueDate;
  final DateTime? issuedAt;

  double get outstanding => totalAmount - amountPaid;
}

final academyInvoicesProvider =
    FutureProvider.family<List<SaasInvoiceRow>, String>((ref, academyId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('saas_invoices')
      .select('id, invoice_number, status, amount, tax_amount, '
          'total_amount, amount_paid, due_date, issued_at')
      .eq('academy_id', academyId)
      .order('issued_at', ascending: false);
  return (rows as List)
      .map((r) => SaasInvoiceRow.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

// ============================================================================
// Platform trends: SaaS revenue + new-academy signups, bucketed into the last
// 12 months (client-side, mirroring the web console's getRevenueByMonth /
// getSignupsByMonth + bucketByMonth helper).
// ============================================================================

class MonthPoint {
  const MonthPoint({required this.month, required this.value});
  final DateTime month; // first day of the month
  final double value;
}

List<MonthPoint> _bucketByMonth(List<({DateTime ts, double amount})> points) {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month);
  final months = <DateTime>[];
  final sums = <String, double>{};
  for (var i = 11; i >= 0; i--) {
    final mth = DateTime(base.year, base.month - i);
    months.add(mth);
    sums['${mth.year}-${mth.month}'] = 0;
  }
  for (final p in points) {
    final key = '${p.ts.year}-${p.ts.month}';
    final cur = sums[key];
    if (cur != null) sums[key] = cur + p.amount;
  }
  return [
    for (final mth in months)
      MonthPoint(month: mth, value: sums['${mth.year}-${mth.month}'] ?? 0),
  ];
}

final revenueByMonthProvider = FutureProvider<List<MonthPoint>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client.from('saas_payments').select('amount, paid_at');
  final points = <({DateTime ts, double amount})>[];
  for (final r in rows as List) {
    final m = r as Map;
    final paidAt = m['paid_at'] as String?;
    if (paidAt == null) continue;
    points.add((
      ts: DateTime.parse(paidAt).toLocal(),
      amount: (m['amount'] as num).toDouble(),
    ));
  }
  return _bucketByMonth(points);
});

final signupsByMonthProvider = FutureProvider<List<MonthPoint>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client.from('academies').select('created_at');
  final points = <({DateTime ts, double amount})>[
    for (final r in rows as List)
      (
        ts: DateTime.parse((r as Map)['created_at'] as String).toLocal(),
        amount: 1.0,
      ),
  ];
  return _bucketByMonth(points);
});
