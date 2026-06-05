import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allPlansProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New plan'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _PlanSheet(),
        ),
      ),
      body: async.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(allPlansProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const AppEmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'No plans yet',
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = rows[i];
              return AppListTile(
                title: Text('${p.name} (${p.code})'),
                subtitle: Text(
                  '₹${p.monthlyPrice.toStringAsFixed(0)}/mo'
                  '${p.yearlyPrice == null ? '' : ' · ₹${p.yearlyPrice!.toStringAsFixed(0)}/yr'}'
                  ' · ${p.isActive ? 'active' : 'inactive'}',
                ),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _PlanSheet(existing: p),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'delete') {
                      await ref.read(superAdminRepoProvider).deletePlan(p.id);
                      ref.invalidate(allPlansProvider);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            },
          );
        },
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
    text: widget.existing?.monthlyPrice.toString() ?? '',
  );
  late final _yearly = TextEditingController(
    text: widget.existing?.yearlyPrice?.toString() ?? '',
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
          context, widget.existing == null ? 'Plan created.' : 'Plan updated.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'New plan' : 'Edit plan',
            style: Theme.of(context).textTheme.titleLarge,
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
                  label: 'Monthly ₹',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppFormField(
                  controller: _yearly,
                  keyboardType: TextInputType.number,
                  label: 'Yearly ₹',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppFormField(
                  controller: _maxStudents,
                  keyboardType: TextInputType.number,
                  label: 'Max students',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppFormField(
                  controller: _maxCoaches,
                  keyboardType: TextInputType.number,
                  label: 'Max coaches',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppFormField(
                  controller: _maxCenters,
                  keyboardType: TextInputType.number,
                  label: 'Max centers',
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Active'),
          ),
          const SizedBox(height: AppSpacing.sm),
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
    );
  }
}
