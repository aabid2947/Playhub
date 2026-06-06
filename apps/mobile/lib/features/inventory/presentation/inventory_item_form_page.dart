import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
      if (!mounted) return;
      AppSnackbar.success(
          context, widget.existing == null ? 'Item created.' : 'Item updated.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(inventoryCategoriesProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final centers = ref.watch(centersProvider).valueOrNull ?? [];
    final isEditing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit item' : 'New item'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const AppSectionHeader(title: 'Details'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppFormField(
                    controller: _name,
                    label: 'Name *',
                    enabled: !_saving,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _sku,
                    label: 'SKU (optional)',
                    enabled: !_saving,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _desc,
                    label: 'Description (optional)',
                    enabled: !_saving,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Stock & cost'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final unitField = AppFormField(
                        controller: _unit,
                        label: 'Unit',
                        enabled: !_saving,
                      );
                      final costField = AppFormField(
                        controller: _unitCost,
                        label: 'Unit cost (₹)',
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                      );
                      // Stack the paired fields on narrow screens so the
                      // inputs never crush to unusable widths.
                      if (constraints.maxWidth < _kStackBelowWidth) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            unitField,
                            const SizedBox(height: AppSpacing.md),
                            costField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: unitField),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: costField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _reorder,
                    label: 'Low-stock threshold',
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Categorisation'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppDropdownField<String?>(
                    label: 'Category',
                    value: _categoryId,
                    items: [
                      const DropdownMenuItem<String?>(child: Text('— None —')),
                      for (final c in categories)
                        DropdownMenuItem<String?>(
                            value: c.id, child: Text(c.name)),
                    ],
                    onChanged:
                        _saving ? null : (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppDropdownField<String?>(
                    label: 'Default vendor',
                    value: _vendorId,
                    items: [
                      const DropdownMenuItem<String?>(child: Text('— None —')),
                      for (final v in vendors)
                        DropdownMenuItem<String?>(
                            value: v.id, child: Text(v.name)),
                    ],
                    onChanged:
                        _saving ? null : (v) => setState(() => _vendorId = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppDropdownField<String?>(
                    label: 'Held at center (optional)',
                    value: _centerId,
                    items: [
                      const DropdownMenuItem<String?>(child: Text('— None —')),
                      for (final c in centers)
                        DropdownMenuItem<String?>(
                            value: c.id, child: Text(c.name)),
                    ],
                    onChanged:
                        _saving ? null : (v) => setState(() => _centerId = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.lg),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEditing ? 'Save changes' : 'Create item'),
          ),
        ),
      ),
    );
  }
}

/// Below this width the paired Unit / Unit cost row stacks vertically.
const double _kStackBelowWidth = 360;
