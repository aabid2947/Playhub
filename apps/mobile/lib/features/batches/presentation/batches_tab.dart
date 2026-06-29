import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/batch_detail_page.dart';
import 'package:playhub/features/batches/presentation/batch_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/features/subscription/data/trial_limits.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class BatchesTab extends ConsumerStatefulWidget {
  const BatchesTab({super.key});

  @override
  ConsumerState<BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends ConsumerState<BatchesTab> {
  String? _sportFilter;

  void _openForm() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const BatchFormPage()),
    );
  }

  void _showTrialLimit(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(batchesProvider);
    final caps = ref.watch(capabilitiesProvider);

    // Free-trial cap: once at the batch limit, the create button prompts to
    // upgrade instead of opening the form (RLS is the hard backstop).
    final limits = ref.watch(trialLimitsProvider).valueOrNull;
    final batchesBlocked = limits?.batchesReached ?? false;

    return Scaffold(
      // Body tab under owner_home_shell's single AppBar — no AppBar here; the
      // in-body header row stands in for it.
      body: Column(
        children: [
          _Header(count: batchesAsync.valueOrNull?.length),
          // The sport chip bar is the single, unified filter for this list —
          // batches only filter on sport, so the chip bar *is* the filter row
          // (mirrors the students/coaches unified-filter pattern).
          SportFilterChipBar(
            selectedId: _sportFilter,
            onSelected: (id) => setState(() => _sportFilter = id),
          ),
          Expanded(
            child: batchesAsync.when(
              loading: () => const AppSkeletonList(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(batchesProvider),
              ),
              data: (batches) {
                // Client-side sport filter (RLS already scopes by academy).
                final list = _sportFilter == null
                    ? batches
                    : batches
                        .where((b) => b.sportId == _sportFilter)
                        .toList();
                if (list.isEmpty) {
                  return const _EmptyState();
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(batchesProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      // Leave room so the last card clears the FAB.
                      AppSpacing.xxl + AppSpacing.xl,
                    ),
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _BatchTile(batch: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: caps.manageBatches
          ? FloatingActionButton.extended(
              heroTag: 'fab-batches',
              onPressed: batchesBlocked
                  ? () => _showTrialLimit(limits!.batchesMessage)
                  : _openForm,
              icon: Icon(batchesBlocked ? Icons.lock_outline : Icons.add),
              label: const Text('New batch'),
            )
          : null,
    );
  }
}

/// The in-body list header: a navy title with a live count badge (the tab has
/// no AppBar), so the sport chip filter below it never reads as an orphaned
/// control.
class _Header extends StatelessWidget {
  const _Header({required this.count});

  /// Live result count for the badge; null while loading.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Text('Batches', style: theme.textTheme.headlineSmall),
            const SizedBox(width: AppSpacing.sm),
            if (count != null)
              AppBadge(
                text: count == 1 ? '1 total' : '$count total',
                tone: AppBadgeTone.brand,
              ),
          ],
        ),
      ),
    );
  }
}

/// A batch card in the v1 list archetype: a gradient sport-icon tile → name +
/// schedule/skill subtitle → a status badge (Open / Almost full / Archived),
/// then a capacity meter ([AppLabeledProgress]) tinted by the sport color.
class _BatchTile extends ConsumerWidget {
  const _BatchTile({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: batch.sportId)),
    );
    final hasSport = sportLabel != '—';
    // Tie the card's accent to the sport (deterministic), falling back to the
    // brand color for an untagged batch.
    final accent =
        hasSport ? colorFromName(sportLabel) : AppPalette.brandPrimary;

    final cap = batch.capacity;
    final fill = (cap == null || cap == 0)
        ? null
        : (batch.enrolledCount / cap).clamp(0.0, 1.0);
    final capacityLabel =
        cap == null ? '${batch.enrolledCount}' : '${batch.enrolledCount}/$cap';

    // One tight subtitle line: schedule, then sport, then skill level.
    final facts = <String>[
      batch.schedule.summary,
      if (hasSport) sportLabel,
      if (batch.skillLevel != null) batch.skillLevel!,
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => BatchDetailPage(batch: batch)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Gradient sport-icon tile (the v1 entity glyph).
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: 0.85), accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  hasSport ? sportIcon(sportLabel) : Icons.schedule_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      batch.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      facts.join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(batch: batch, fill: fill),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Capacity meter — bar + enrolled/cap trailing, tinted by the sport.
          // Falls back to a plain count line when the batch has no capacity to
          // measure against.
          if (fill != null)
            AppLabeledProgress(
              label: 'Capacity',
              value: fill,
              trailing: capacityLabel,
              color: accent,
            )
          else
            Row(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  capacityLabel == '0'
                      ? 'No students enrolled'
                      : '$capacityLabel enrolled',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: AppType.semibold,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Status pill for a batch row: an archived batch always reads "Archived";
/// otherwise the capacity fill drives Open → Almost full → Full.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.batch, required this.fill});
  final Batch batch;

  /// Capacity fill 0..1, or null when the batch has no capacity set.
  final double? fill;

  @override
  Widget build(BuildContext context) {
    if (!batch.isActive) {
      return const AppBadge(text: 'Archived');
    }
    final f = fill;
    if (f == null) {
      return const AppBadge(text: 'Open', tone: AppBadgeTone.success);
    }
    if (f >= 1) {
      return const AppBadge(text: 'Full', tone: AppBadgeTone.warning);
    }
    if (f >= 0.9) {
      return const AppBadge(text: 'Almost full', tone: AppBadgeTone.warning);
    }
    return const AppBadge(text: 'Open', tone: AppBadgeTone.success);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.schedule_outlined,
      title: 'No batches yet',
      subtitle: 'Tap "New batch" to schedule your first session.',
    );
  }
}
