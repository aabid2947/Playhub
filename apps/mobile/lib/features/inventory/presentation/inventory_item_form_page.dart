import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
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
  // Unit is a MEASURE (piece, pair, kg), never a quantity. It used to be a free
  // text box pre-filled "piece", and owners typed the quantity into it ("20
  // piece") — which left stock at 0 and rendered as "0 20 piece" in the list.
  // A picker makes that mistake impossible; "Other" still allows a custom
  // measure, validated to contain no digits.
  late String _unitChoice = _initialUnitChoice();
  late final _unitOther = TextEditingController(
    text: _kCommonUnits.contains(widget.existing?.unit)
        ? ''
        : (widget.existing?.unit ?? ''),
  );
  late final _unitCost = TextEditingController(
      text: widget.existing?.unitCost.toString() ?? '0');
  late final _reorder = TextEditingController(
      text: widget.existing?.reorderThreshold.toString() ?? '0');
  // Quantity in stock. on_hand is driven entirely by movements (the
  // sync_item_on_hand trigger), so this never writes the column directly — it
  // records an opening "in" movement. Offered on create, and on edit while the
  // item is still at zero, so an item saved without stock can be corrected
  // without hunting for the movement sheet.
  final _openingStock = TextEditingController();

  String _initialUnitChoice() {
    final existing = widget.existing?.unit;
    if (existing == null || existing.isEmpty) return 'piece';
    return _kCommonUnits.contains(existing) ? existing : _kUnitOther;
  }

  /// The measure to save: the picked one, or the typed custom (falling back to
  /// 'piece' so the column is never blank).
  String get _resolvedUnit {
    if (_unitChoice != _kUnitOther) return _unitChoice;
    final custom = _unitOther.text.trim();
    return custom.isEmpty ? 'piece' : custom;
  }

  /// True while the item has no stock — the only state where an opening entry
  /// makes sense on an existing item.
  bool get _canSeedStock =>
      widget.existing == null || widget.existing!.onHand == 0;
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
    for (final c in [
      _name,
      _sku,
      _desc,
      _unitOther,
      _unitCost,
      _reorder,
      _openingStock,
    ]) {
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
      final item = await repo.upsertItem(
        id: widget.existing?.id,
        name: _name.text.trim(),
        sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        unit: _resolvedUnit,
        unitCost: double.tryParse(_unitCost.text.trim()) ?? 0,
        reorderThreshold: double.tryParse(_reorder.text.trim()) ?? 0,
        categoryId: _categoryId,
        vendorId: _vendorId,
        centerId: _centerId,
      );
      // Seed the opening stock as an "in" movement — on_hand is trigger-driven
      // from the ledger, so an item stays at 0 unless the starting quantity is
      // recorded as an entry. Also offered when editing an item still at zero,
      // so one saved without stock can be fixed here.
      if (_canSeedStock) {
        final opening = double.tryParse(_openingStock.text.trim()) ?? 0;
        if (opening > 0) {
          await repo.recordMovement(
            itemId: item.id,
            kind: 'in',
            qty: opening,
            centerId: item.centerId, // opening stock lands at the item's location
            reference: 'Opening stock',
          );
        }
      }
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
            const AppSectionHeader(
              title: 'Details',
              icon: Icons.inventory_2_outlined,
            ),
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
            const AppSectionHeader(
              title: 'Stock & cost',
              icon: Icons.inventory_outlined,
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quantity FIRST — it's the number owners come here to set,
                  // and putting it above the measure stops "20 piece" being
                  // typed into the unit box.
                  if (_canSeedStock) ...[
                    AppFormField(
                      controller: _openingStock,
                      label: isEditing ? 'Stock in hand' : 'Opening stock',
                      hint: 'How many you have right now, e.g. 30',
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      // Whole count only — what you type is what stock shows.
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final unitField = AppDropdownField<String>(
                        label: 'Unit (how it is counted)',
                        value: _unitChoice,
                        items: [
                          for (final u in _kCommonUnits)
                            DropdownMenuItem(value: u, child: Text(u)),
                          const DropdownMenuItem(
                            value: _kUnitOther,
                            child: Text('Other…'),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) =>
                                setState(() => _unitChoice = v ?? 'piece'),
                      );
                      final costField = AppFormField(
                        controller: _unitCost,
                        label: 'Unit cost (₹)',
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        // Numeric only — digits + a single decimal point.
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                        ],
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
                  // The custom measure, only when "Other…" is picked. Digits are
                  // rejected: a unit is "pair", never "20 pair".
                  if (_unitChoice == _kUnitOther) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppFormField(
                      controller: _unitOther,
                      label: 'Unit name *',
                      hint: 'e.g. bundle, crate',
                      enabled: !_saving,
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Required';
                        if (RegExp(r'\d').hasMatch(t)) {
                          return 'No numbers here — put the quantity in '
                              '${isEditing ? 'Stock in hand' : 'Opening stock'}';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _reorder,
                    label: 'Low-stock threshold',
                    hint: 'Warn me when stock falls to this',
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    // Whole count only — no letters / decimals.
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  // An item already holding stock changes it through the
                  // movement sheet (purchase / sale / return), so the ledger
                  // stays the single source of truth.
                  if (isEditing && !_canSeedStock) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'To change the stock count, use Purchase / Sale on the '
                      "item's page — that keeps the stock history correct.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(
              title: 'Categorisation',
              icon: Icons.category_outlined,
            ),
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
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: AppShadows.floating,
        ),
        child: SafeArea(
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
      ),
    );
  }
}

/// Below this width the paired Unit / Unit cost row stacks vertically.
const double _kStackBelowWidth = 360;

/// Sentinel for the "Other…" option in the unit picker.
const String _kUnitOther = '__other__';

/// The measures offered in the unit picker. Anything else goes through
/// "Other…" — the point is that the field can't be mistaken for a quantity.
const List<String> _kCommonUnits = [
  'piece',
  'pair',
  'set',
  'box',
  'packet',
  'dozen',
  'kg',
  'gram',
  'litre',
  'metre',
];
