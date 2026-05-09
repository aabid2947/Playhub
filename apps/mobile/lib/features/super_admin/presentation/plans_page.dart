import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';

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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) return const Center(child: Text('No plans yet'));
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = rows[i];
              return ListTile(
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
  late final _desc =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _monthly = TextEditingController(
      text: widget.existing?.monthlyPrice.toString() ?? '');
  late final _yearly = TextEditingController(
      text: widget.existing?.yearlyPrice?.toString() ?? '');
  late final _maxStudents = TextEditingController(
      text: widget.existing?.maxStudents?.toString() ?? '');
  late final _maxCoaches = TextEditingController(
      text: widget.existing?.maxCoaches?.toString() ?? '');
  late final _maxCenters = TextEditingController(
      text: widget.existing?.maxCenters?.toString() ?? '');
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
      await ref.read(superAdminRepoProvider).upsertPlan(
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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'New plan' : 'Edit plan',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  decoration:
                      const InputDecoration(labelText: 'Code (e.g. basic)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _monthly,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Monthly ₹'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _yearly,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Yearly ₹'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxStudents,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max students'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _maxCoaches,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max coaches'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _maxCenters,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max centers'),
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
          const SizedBox(height: 8),
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
