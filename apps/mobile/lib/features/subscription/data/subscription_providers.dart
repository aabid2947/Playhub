import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart' show PlanRow;

class AcademySubscription {
  const AcademySubscription({
    required this.id,
    required this.academyId,
    required this.planId,
    required this.status,
    required this.billingCycle,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    this.trialEndsAt,
    this.cancelledAt,
  });

  factory AcademySubscription.fromMap(Map<String, dynamic> m) =>
      AcademySubscription(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        planId: m['plan_id'] as String,
        status: m['status'] as String,
        billingCycle: m['billing_cycle'] as String,
        currentPeriodStart:
            DateTime.parse(m['current_period_start'] as String).toLocal(),
        currentPeriodEnd:
            DateTime.parse(m['current_period_end'] as String).toLocal(),
        trialEndsAt: m['trial_ends_at'] == null
            ? null
            : DateTime.parse(m['trial_ends_at'] as String).toLocal(),
        cancelledAt: m['cancelled_at'] == null
            ? null
            : DateTime.parse(m['cancelled_at'] as String).toLocal(),
      );

  final String id;
  final String academyId;
  final String planId;
  final String status;
  final String billingCycle;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final DateTime? trialEndsAt;
  final DateTime? cancelledAt;

  /// Mirrors the DB `academy_writes_allowed()` gate: management writes are
  /// allowed while active/past_due, or on a trial that has not yet expired.
  bool get writesAllowed =>
      status == 'active' ||
      status == 'past_due' ||
      (status == 'trial' &&
          (trialEndsAt == null || trialEndsAt!.isAfter(DateTime.now())));

  /// Frozen — suspended, cancelled, or an expired trial. Owners/admins are
  /// routed to the paywall; everyone else stays read-only (RLS enforces it).
  bool get isBlocked => !writesAllowed;

  bool get isTrial => status == 'trial';

  /// Whole days until the trial ends (negative once expired); null if not a trial.
  int? get trialDaysLeft => trialEndsAt?.difference(DateTime.now()).inDays;

  /// Still operational but the trial lapses within 3 days — warn the owner.
  bool get isTrialEndingSoon {
    final d = trialDaysLeft;
    return isTrial && writesAllowed && d != null && d <= 3;
  }
}

class SaasInvoice {
  const SaasInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.status,
    required this.totalAmount,
    required this.amountPaid,
    required this.dueDate,
    required this.issuedAt,
  });

  factory SaasInvoice.fromMap(Map<String, dynamic> m) => SaasInvoice(
        id: m['id'] as String,
        invoiceNumber: m['invoice_number'] as String,
        status: m['status'] as String,
        totalAmount: (m['total_amount'] as num).toDouble(),
        amountPaid: (m['amount_paid'] as num?)?.toDouble() ?? 0,
        dueDate: DateTime.parse(m['due_date'] as String),
        issuedAt: DateTime.parse(m['issued_at'] as String).toLocal(),
      );

  final String id;
  final String invoiceNumber;
  final String status;
  final double totalAmount;
  final double amountPaid;
  final DateTime dueDate;
  final DateTime issuedAt;

  double get balance => totalAmount - amountPaid;
}

final mySubscriptionProvider =
    FutureProvider<AcademySubscription?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  final r = await client
      .from('academy_subscriptions')
      .select()
      .eq('academy_id', profile!.academyId!)
      .maybeSingle();
  return r == null ? null : AcademySubscription.fromMap(r);
});

final mySaasInvoicesProvider =
    FutureProvider<List<SaasInvoice>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('saas_invoices')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('issued_at', ascending: false);
  return (rows as List)
      .map((r) => SaasInvoice.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final availablePlansProvider = FutureProvider<List<PlanRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('subscription_plans')
      .select()
      .eq('is_active', true)
      .order('monthly_price');
  return (rows as List)
      .map((r) => PlanRow.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});
