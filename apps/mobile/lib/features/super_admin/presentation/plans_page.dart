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
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: AppSectionHeader(
            title: 'Subscription plans',
            trailing: TextButton.icon(
              onPressed: () => _openSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('New plan'),
            ),
          ),
        ),
        Expanded(
          child: async.when(
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
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = rows[i];
                    return AppListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: Text('${p.name} (${p.code})'),
                      subtitle: Text(_priceLine(p)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppBadge(
                            text: p.isActive ? 'Active' : 'Inactive',
                            tone: p.isActive
                                ? AppBadgeTone.success
                                : AppBadgeTone.neutral,
                          ),
                          IconButton(
                            tooltip: 'Delete plan',
                            icon: Icon(
                              Icons.delete_outline,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () => _confirmDelete(context, ref, p),
                          ),
                        ],
                      ),
                      onTap: () => _openSheet(context, existing: p),
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

  /// "₹999/mo · ₹9,999/yr" — yearly omitted when unset.
  String _priceLine(PlanRow p) {
    final monthly = '₹${p.monthlyPrice.toStringAsFixed(0)}/mo';
    if (p.yearlyPrice == null) return monthly;
    return '$monthly · ₹${p.yearlyPrice!.toStringAsFixed(0)}/yr';
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
              Text(
                widget.existing == null ? 'New plan' : 'Edit plan',
                style: theme.textTheme.titleLarge,
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
