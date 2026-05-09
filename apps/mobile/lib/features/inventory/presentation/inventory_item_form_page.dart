import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';

class InventoryItemFormPage extends ConsumerStatefulWidget {
  const InventoryItemFormPage({this.existing, super.key});
  final InventoryItem? existing;

  @override
  ConsumerState<InventoryItemFormPage> createState() =>
      _InventoryItemFormPageState();
}

class _InventoryItemFormPageState extends ConsumerState<InventoryItemFormPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _sku = TextEditingController(text: widget.existing?.sku ?? '');
  late final _desc =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _unit =
      TextEditingController(text: widget.existing?.unit ?? 'piece');
  late final _unitCost = TextEditingController(
      text: widget.existing?.unitCost.toString() ?? '0');
  late final _reorder = TextEditingController(
      text: widget.existing?.reorderThreshold.toString() ?? '0');
  String? _categoryId;
  String? _vendorId;
  String? _centerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?.categoryId;
    _vendorId = widget.existing?.vendorId;
    _centerId = widget.existing?.centerId;
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _desc, _unit, _unitCost, _reorder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(inventoryRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.upsertItem(
        id: widget.existing?.id,
        name: _name.text.trim(),
        sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        unit: _unit.text.trim().isEmpty ? 'piece' : _unit.text.trim(),
        unitCost: double.tryParse(_unitCost.text.trim()) ?? 0,
        reorderThreshold: double.tryParse(_reorder.text.trim()) ?? 0,
        categoryId: _categoryId,
        vendorId: _vendorId,
        centerId: _centerId,
      );
      ref.invalidate(inventoryItemsProvider);
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
    final categories = ref.watch(inventoryCategoriesProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final centers = ref.watch(centersProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New item' : 'Edit item'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sku,
              decoration: const InputDecoration(labelText: 'SKU (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Description'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _unitCost,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Unit cost (₹)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reorder,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Low-stock threshold'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<String?>(child: Text('— None —')),
                for (final c in categories)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _vendorId,
              decoration: const InputDecoration(labelText: 'Default vendor'),
              items: [
                const DropdownMenuItem<String?>(child: Text('— None —')),
                for (final v in vendors)
                  DropdownMenuItem<String?>(value: v.id, child: Text(v.name)),
              ],
              onChanged: (v) => setState(() => _vendorId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _centerId,
              decoration:
                  const InputDecoration(labelText: 'Held at center (optional)'),
              items: [
                const DropdownMenuItem<String?>(child: Text('— None —')),
                for (final c in centers)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _centerId = v),
            ),
            const SizedBox(height: 24),
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
    );
  }
}
