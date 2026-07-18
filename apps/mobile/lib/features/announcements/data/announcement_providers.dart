import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/announcements/data/announcement.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All announcements visible to the current user (admin sees full history,
/// other roles see whatever the academy_id-scoped read policy returns).
final announcementsListProvider =
    FutureProvider<List<Announcement>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('announcements')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => Announcement.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

/// The audience-filtered feed for the current user — joins recipients to
/// only show announcements actually targeted at them. Carries read_at so
/// the UI can show unread badges.
class AnnouncementFeedItem {
  const AnnouncementFeedItem({
    required this.announcement,
    required this.recipientId,
    this.readAt,
  });
  final Announcement announcement;
  final String recipientId;
  final DateTime? readAt;
}

final announcementFeedProvider =
    FutureProvider<List<AnnouncementFeedItem>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final client = ref.watch(supabaseClientProvider);
  if (userId == null) return const [];
  final rows = await client
      .from('announcement_recipients')
      .select('id, read_at, announcements(*)')
      .eq('user_id', userId)
      .order('delivered_at', ascending: false);
  return (rows as List).map((r) {
    final m = r as Map<String, dynamic>;
    final ann = Announcement.fromMap(
      (m['announcements'] as Map).cast<String, dynamic>(),
    );
    return AnnouncementFeedItem(
      announcement: ann,
      recipientId: m['id'] as String,
      readAt: m['read_at'] == null
          ? null
          : DateTime.parse(m['read_at'] as String).toLocal(),
    );
  }).toList(growable: false);
});

class AnnouncementsRepo {
  AnnouncementsRepo(this._client, this._academyId);
  final SupabaseClient _client;
  final String _academyId;

  Future<Announcement> draft({
    required String subject,
    required String body,
    String? id,
    List<String> targetRoles = const [],
    List<String> targetBatches = const [],
    List<String> targetCenters = const [],
    List<String> targetSports = const [],
    List<AnnouncementMedia> media = const [],
    bool viaPush = true,
    bool viaEmail = false,
    bool viaInApp = true,
    DateTime? scheduledFor,
  }) async {
    final r = await _client
        .from('announcements')
        .insert({
          // Allow a client-generated id so media can be uploaded to its
          // storage folder before the row is inserted (see the composer).
          if (id != null) 'id': id,
          'academy_id': _academyId,
          'subject': subject,
          'body': body,
          'target_roles': targetRoles,
          'target_batches': targetBatches,
          'target_centers': targetCenters,
          'target_sports': targetSports,
          'media': media.map((m) => m.toMap()).toList(),
          'via_push': viaPush,
          'via_email': viaEmail,
          'via_in_app': viaInApp,
          if (scheduledFor != null)
            'scheduled_for': scheduledFor.toUtc().toIso8601String(),
          'created_by': _client.auth.currentUser?.id,
        })
        .select()
        .maybeSingle();
    // A null row means the insert was blocked by RLS (targeting outside the
    // composer's scope) rather than a not-found — surface it as a permission
    // error, mirroring the createStudent/updateBatch pattern.
    if (r == null) {
      throw const PostgrestException(
        message: 'You can only announce within your own scope.',
        code: '42501',
      );
    }
    return Announcement.fromMap(r);
  }

  /// Calls the send-announcement Edge Function which fans out push + email
  /// + in-app and sets sent_at/sent_count/failed_count.
  Future<void> sendNow(String announcementId) async {
    final res = await _client.functions.invoke(
      'send-announcement',
      body: {'announcement_id': announcementId},
    );
    final body = res.data as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw StateError(body['error']?.toString() ?? 'send failed');
    }
  }

  Future<void> markRead(String announcementId) async {
    await _client.rpc('mark_announcement_read',
        params: {'p_announcement_id': announcementId});
  }
}

final announcementsRepoProvider =
    FutureProvider<AnnouncementsRepo?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  return AnnouncementsRepo(
    ref.watch(supabaseClientProvider),
    profile!.academyId!,
  );
});

/// One selectable audience entry (a batch, sport, or center) for the composer.
class AudienceOption {
  const AudienceOption({required this.id, required this.label});
  final String id;
  final String label;
}

/// The audience targets the current user is *allowed* to pick, scoped to their
/// role — so the composer never offers a target RLS (can_target_announcement)
/// would reject:
///   • admin tier  → roles + all batches/sports/centers in the academy
///   • center_admin → their own center + its sports + its batches
///   • head_coach   → their own sports + their manageable batches
///   • coach        → only their own batches
class ComposerAudience {
  const ComposerAudience({
    required this.role,
    required this.batches,
    required this.sports,
    required this.centers,
    required this.ownCenterId,
    required this.ownCenterLabel,
  });

  final String role;
  final List<AudienceOption> batches;
  final List<AudienceOption> sports;
  final List<AudienceOption> centers;
  final String? ownCenterId;
  final String? ownCenterLabel;

  bool get _isAdmin => role == 'academy_owner' || role == 'academy_admin';
  bool get canTargetRoles => _isAdmin;
  bool get canTargetCenters => _isAdmin || role == 'center_admin';
  bool get canTargetSports =>
      _isAdmin || role == 'center_admin' || role == 'head_coach';
}

final composerAudienceProvider = FutureProvider<ComposerAudience>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final role = profile?.role ?? '';
  final academyId = profile?.academyId;
  if (academyId == null) {
    return ComposerAudience(
      role: role,
      batches: const [],
      sports: const [],
      centers: const [],
      ownCenterId: null,
      ownCenterLabel: null,
    );
  }
  final client = ref.watch(supabaseClientProvider);
  final isAdmin = role == 'academy_owner' || role == 'academy_admin';

  // --- Batches -------------------------------------------------------------
  // admin + center_admin read batches academy-wide (RLS center-narrows the
  // center_admin's read), so a plain query already returns the right set.
  // coach / head_coach reuse the scoped "my manageable batches" provider.
  List<AudienceOption> batches;
  if (isAdmin || role == 'center_admin') {
    final rows = await client
        .from('batches')
        .select('id, name')
        .eq('academy_id', academyId)
        .eq('is_active', true)
        .order('name');
    batches = [
      for (final r in rows as List)
        AudienceOption(id: (r as Map)['id'] as String, label: r['name'] as String),
    ];
  } else {
    final mine = await ref.watch(myBatchesProvider.future);
    batches = [for (final b in mine) AudienceOption(id: b.id, label: b.name)];
  }

  // --- Sports --------------------------------------------------------------
  List<AudienceOption> sports;
  if (isAdmin) {
    final all = await ref.watch(allSportsProvider.future);
    sports = [for (final s in all) AudienceOption(id: s.id, label: s.name)];
  } else if (role == 'center_admin' && profile!.centerId != null) {
    final cs = await ref.watch(centerSportsProvider(profile.centerId!).future);
    sports = [
      for (final s in cs) AudienceOption(id: s.sport.id, label: s.displayName),
    ];
  } else if (role == 'head_coach') {
    final ids = await ref.watch(mySportIdsProvider.future);
    if (ids.isEmpty) {
      sports = const [];
    } else {
      final all = await ref.watch(allSportsProvider.future);
      final byId = {for (final s in all) s.id: s.name};
      sports = [
        for (final id in ids) AudienceOption(id: id, label: byId[id] ?? 'Sport'),
      ];
    }
  } else {
    sports = const [];
  }

  // --- Centers -------------------------------------------------------------
  List<AudienceOption> centers;
  String? ownCenterLabel;
  if (isAdmin) {
    final list = await ref.watch(centersProvider.future);
    centers = [for (final c in list) AudienceOption(id: c.id, label: c.name)];
  } else if (role == 'center_admin' && profile!.centerId != null) {
    final list = await ref.watch(centersProvider.future);
    final mine = list.where((c) => c.id == profile.centerId).toList();
    centers = [for (final c in mine) AudienceOption(id: c.id, label: c.name)];
    ownCenterLabel = mine.isEmpty ? 'My center' : mine.first.name;
  } else {
    centers = const [];
  }

  return ComposerAudience(
    role: role,
    batches: batches,
    sports: sports,
    centers: centers,
    ownCenterId: profile?.centerId,
    ownCenterLabel: ownCenterLabel,
  );
});
