import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// App-bar-less list body hosted inside the super-admin shell's IndexedStack.
/// The shell owns the (constant) AppBar, so this page is a bare body — no
/// Scaffold/AppBar of its own.
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  void _openSheet(BuildContext context, {PlanRow? existing}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlanSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PlanRow plan,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete plan?'),
        content: Text(
          'Delete "${plan.name}" (${plan.code})? This cannot be undone. '
          'Academies already on this plan are not migrated automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(superAdminRepoProvider).deletePlan(plan.id);
    ref.invalidate(allPlansProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allPlansProvider);

    return Stack(
      children: [
        async.when(
          loading: () => const AppSkeletonList(),
          error: (e, _) => AppErrorView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(allPlansProvider),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return AppEmptyState(
                icon: Icons.workspace_premium_outlined,
                title: 'No plans yet',
                subtitle: 'Create the first subscription plan academies can '
                    'be billed on.',
                actionLabel: 'New plan',
                onAction: () => _openSheet(context),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(allPlansProvider),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  // Leave room so the last card clears the FAB.
                  AppSpacing.xxl + AppSpacing.xl,
                ),
                itemCount: rows.length + 1,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) {
                  if (i == 0) return _ListHeader(count: rows.length);
                  final p = rows[i - 1];
                  return _PlanCard(
                    plan: p,
                    onEdit: () => _openSheet(context, existing: p),
                    onDelete: () => _confirmDelete(context, ref, p),
                  );
                },
              ),
            );
          },
        ),
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: FloatingActionButton.extended(
            onPressed: () => _openSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('New plan'),
          ),
        ),
      ],
    );
  }
}

/// In-body list header: title + a live count [AppBadge] (archetype B).
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'Subscription plans',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: AppType.bold,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppBadge(
          text: count == 1 ? '1 plan' : '$count plans',
          tone: AppBadgeTone.brand,
        ),
      ],
    );
  }
}

/// One subscription plan as a v1 card: a colored workspace-icon tile → name +
/// code → price line → seat/center limit chips, with the active/inactive
/// [AppBadge] and a delete affordance. Tap the card to edit.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.onEdit,
    required this.onDelete,
  });

  final PlanRow plan;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = colorFromName(plan.code);

    final limits = <(IconData, String)>[
      (Icons.groups_outlined, _limitLabel(plan.maxStudents, 'students')),
      (Icons.sports_outlined, _limitLabel(plan.maxCoaches, 'coaches')),
      (Icons.location_city_outlined, _limitLabel(plan.maxCenters, 'centers')),
    ];

    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.workspace_premium_outlined,
                  color: tint,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plan.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: AppType.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        AppBadge(
                          text: plan.isActive ? 'Active' : 'Inactive',
                          tone: plan.isActive
                              ? AppBadgeTone.success
                              : AppBadgeTone.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.code,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _priceLine(plan),
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.primary,
              fontWeight: AppType.bold,
            ),
          ),
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              plan.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final (icon, label) in limits)
                      _LimitChip(icon: icon, label: label),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete plan',
                icon: Icon(
                  Icons.delete_outline,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "1,000 students" for a cap, or "Unlimited students" when null.
  String _limitLabel(int? value, String noun) =>
      value == null ? 'Unlimited $noun' : '$value $noun';

  /// "₹999/mo · ₹9,999/yr" — yearly omitted when unset.
  String _priceLine(PlanRow p) {
    final monthly = '₹${p.monthlyPrice.toStringAsFixed(0)}/mo';
    if (p.yearlyPrice == null) return monthly;
    return '$monthly · ₹${p.yearlyPrice!.toStringAsFixed(0)}/yr';
  }
}

/// A small, icon-led limit summary pill (e.g. "Unlimited students").
class _LimitChip extends StatelessWidget {
  const _LimitChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: AppType.semibold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSheet extends ConsumerStatefulWidget {
  const _PlanSheet({this.existing});
  final PlanRow? existing;

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _desc = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _monthly = TextEditingController(
    text: widget.existing?.monthlyPrice.toStringAsFixed(0) ?? '',
  );
  late final _yearly = TextEditingController(
    text: widget.existing?.yearlyPrice?.toStringAsFixed(0) ?? '',
  );
  late final _maxStudents = TextEditingController(
    text: widget.existing?.maxStudents?.toString() ?? '',
  );
  late final _maxCoaches = TextEditingController(
    text: widget.existing?.maxCoaches?.toString() ?? '',
  );
  late final _maxCenters = TextEditingController(
    text: widget.existing?.maxCenters?.toString() ?? '',
  );
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _active = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _code,
      _name,
      _desc,
      _monthly,
      _yearly,
      _maxStudents,
      _maxCoaches,
      _maxCenters,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(superAdminRepoProvider)
          .upsertPlan(
            id: widget.existing?.id,
            code: _code.text.trim(),
            name: _name.text.trim(),
            description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
            monthlyPrice: double.tryParse(_monthly.text.trim()) ?? 0,
            yearlyPrice: double.tryParse(_yearly.text.trim()),
            maxStudents: int.tryParse(_maxStudents.text.trim()),
            maxCoaches: int.tryParse(_maxCoaches.text.trim()),
            maxCenters: int.tryParse(_maxCenters.text.trim()),
            isActive: _active,
          );
      ref.invalidate(allPlansProvider);
      if (!mounted) return;
      AppSnackbar.success(
        context,
        widget.existing == null ? 'Plan created.' : 'Plan updated.',
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        // Keep the sheet scrollable + height-bounded so a tall (limits +
        // keyboard) layout never clips.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      Icons.workspace_premium_outlined,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    widget.existing == null ? 'New plan' : 'Edit plan',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: AppType.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppFormField(
                      controller: _code,
                      label: 'Code (e.g. basic)',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppFormField(controller: _name, label: 'Name'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(controller: _desc, label: 'Description'),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppFormField(
                      controller: _monthly,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      label: 'Monthly ₹',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppFormField(
                      controller: _yearly,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      label: 'Yearly ₹',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const AppSectionHeader(title: 'Limits'),
              Text(
                'Leave a field blank for unlimited.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Stack the three limit fields vertically so each stays a usable
              // width on a phone (the old 3-up row crushed them).
              _LimitField(
                controller: _maxStudents,
                label: 'Max students',
              ),
              const SizedBox(height: AppSpacing.md),
              _LimitField(
                controller: _maxCoaches,
                label: 'Max coaches',
              ),
              const SizedBox(height: AppSpacing.md),
              _LimitField(
                controller: _maxCenters,
                label: 'Max centers',
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive plans are hidden from new subscriptions.',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A numeric limit input that shows a live "Unlimited" hint when left blank,
/// so super-admins can tell "unlimited" (blank) from a real cap at a glance.
class _LimitField extends StatefulWidget {
  const _LimitField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  State<_LimitField> createState() => _LimitFieldState();
}

class _LimitFieldState extends State<_LimitField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnlimited = widget.controller.text.trim().isEmpty;
    return AppFormField(
      controller: widget.controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      label: widget.label,
      suffixIcon: isUnlimited
          ? Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Align(
                widthFactor: 1,
                child: Text(
                  'Unlimited',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
