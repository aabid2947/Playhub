import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Sentinel for "Head office" in the location pickers — the DB models HO as a
/// NULL center_id, but null can't double as "nothing picked", so we use this.
const String _kHeadOffice = '__ho__';

/// Bottom sheet for recording a stock movement (in / out / return / adjustment).
class MovementSheet extends ConsumerStatefulWidget {
  const MovementSheet({required this.item, super.key});
  final InventoryItem item;

  @override
  ConsumerState<MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends ConsumerState<MovementSheet> {
  final _formKey = GlobalKey<FormState>();
  String _kind = 'in';
  final _qty = TextEditingController(text: '1');
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  String? _studentId;
  String? _coachId;
  // Location the entry affects. For a transfer, [_location] is the SOURCE and
  // [_toLocation] the DESTINATION. `_kHeadOffice` = HO (saved as null center_id);
  // a null _toLocation means "not picked yet".
  String _location = _kHeadOffice;
  String _fromLocation = _kHeadOffice;
  String? _toLocation;
  bool _saving = false;

  /// Out and Return movements are tied to a person; In and Adjust are not.
  bool get _needsRecipient => _kind == 'out' || _kind == 'return';

  bool get _isTransfer => _kind == 'transfer';

  /// Map a picker value to a center_id (HO sentinel → null).
  static String? _toCenterId(String? loc) =>
      (loc == null || loc == _kHeadOffice) ? null : loc;

  @override
  void dispose() {
    _qty.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Inline validator mirrored by the submit guard: a non-zero number, and
  /// positive unless this is a signed adjustment.
  String? _validateQty(String? raw) {
    final value = double.tryParse((raw ?? '').trim());
    if (value == null) return 'Enter a number.';
    if (value == 0) return 'Quantity must not be zero.';
    if (_kind != 'adjustment' && value < 0) {
      return 'Use a positive number.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    if (qty == 0) {
      AppSnackbar.error(context, 'Enter a non-zero quantity.');
      return;
    }
    // Resolve the affected location(s) and guard transfers.
    final String? centerId;
    final String? toCenterId;
    if (_isTransfer) {
      if (_toLocation == null) {
        AppSnackbar.error(context, 'Pick a destination location.');
        return;
      }
      if (_fromLocation == _toLocation) {
        AppSnackbar.error(context, 'Source and destination must differ.');
        return;
      }
      centerId = _toCenterId(_fromLocation);
      toCenterId = _toCenterId(_toLocation);
    } else {
      centerId = _toCenterId(_location);
      toCenterId = null;
    }
    setState(() => _saving = true);
    try {
      final repo = await ref.read(inventoryRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.recordMovement(
        itemId: widget.item.id,
        kind: _kind,
        qty: qty,
        centerId: centerId,
        toCenterId: toCenterId,
        studentId: _studentId,
        coachId: _coachId,
        vendorId: widget.item.vendorId,
        reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      ref
        ..invalidate(itemMovementsProvider(widget.item.id))
        ..invalidate(itemStockProvider(widget.item.id))
        ..invalidate(inventoryItemsProvider);
      if (!mounted) return;
      AppSnackbar.success(
          context, _isTransfer ? 'Transfer recorded.' : 'Movement recorded.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final coaches =
        ref.watch(coachesProvider).valueOrNull ?? const <Coach>[];
    final centers = ref.watch(centersProvider).valueOrNull ?? const [];
    final activeCenters = centers.where((c) => c.isActive).toList();
    // Location options: Head office (HO) + every active center.
    final locationItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: _kHeadOffice, child: Text('Head office')),
      for (final c in activeCenters)
        DropdownMenuItem(value: c.id, child: Text(c.name)),
    ];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            _Header(item: widget.item),
            const Divider(height: 1),
            Flexible(
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  shrinkWrap: true,
                  children: [
                    const AppSectionHeader(
                      title: 'Entry type',
                      icon: Icons.swap_vert_rounded,
                    ),
                    // Five kinds (incl. Transfer) — a dropdown scales better
                    // than a segmented button and reads in business terms.
                    AppDropdownField<String>(
                      label: 'Type',
                      value: _kind,
                      items: [
                        for (final k in const [
                          'in',
                          'out',
                          'return',
                          'adjustment',
                          'transfer',
                        ])
                          DropdownMenuItem(
                            value: k,
                            child: Text(kInventoryKindLabels[k]!),
                          ),
                      ],
                      onChanged: (v) => setState(() => _kind = v ?? _kind),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      kInventoryKindHints[_kind] ?? '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Quantity',
                      icon: Icons.tag_rounded,
                    ),
                    AppFormField(
                      controller: _qty,
                      label: _kind == 'adjustment'
                          ? 'Qty (signed — negative reduces stock)'
                          : 'Qty (positive number)',
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      validator: _validateQty,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Location — for a transfer this is From + To; otherwise the
                    // single location the entry posts to.
                    AppSectionHeader(
                      title: _isTransfer ? 'Move between' : 'Location',
                      icon: Icons.place_outlined,
                    ),
                    if (_isTransfer) ...[
                      AppDropdownField<String>(
                        label: 'From',
                        value: _fromLocation,
                        items: locationItems,
                        onChanged: (v) =>
                            setState(() => _fromLocation = v ?? _fromLocation),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppDropdownField<String>(
                        label: 'To *',
                        value: _toLocation,
                        items: locationItems,
                        onChanged: (v) => setState(() => _toLocation = v),
                      ),
                    ] else
                      AppDropdownField<String>(
                        label: 'Location',
                        value: _location,
                        items: locationItems,
                        onChanged: (v) =>
                            setState(() => _location = v ?? _location),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    // Recipient is always mounted so toggling the kind never
                    // reflows the sheet; it just enables/disables in place.
                    _RecipientSection(
                      enabled: _needsRecipient,
                      students: students,
                      coaches: coaches,
                      studentId: _studentId,
                      coachId: _coachId,
                      onStudentChanged: (v) =>
                          setState(() => _studentId = v),
                      onCoachChanged: (v) => setState(() => _coachId = v),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Details',
                      icon: Icons.notes_rounded,
                    ),
                    AppFormField(
                      controller: _ref,
                      label: 'Reference (PO #, etc.)',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppFormField(
                      controller: _notes,
                      label: 'Notes',
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            // Pinned action bar with a floating lift so it reads as a
            // deliberate commit, separate from the scrolling form above.
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: AppShadows.floating,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
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
                          : const Text('Record'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded drag affordance at the top of the sheet.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}

/// Title row: a clear task title + the item being moved and its current
/// on-hand, plus a close button so the sheet reads as a deliberate action.
class _Header extends StatelessWidget {
  const _Header({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onHand = item.onHand == item.onHand.roundToDouble()
        ? item.onHand.toStringAsFixed(0)
        : item.onHand.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Record movement',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${item.name} · $onHand ${item.unit} on hand',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Student + coach recipient pickers. Always rendered so switching the
/// movement kind never changes the sheet's height; the fields are simply
/// disabled (and a hint shown) for kinds that don't take a recipient.
class _RecipientSection extends StatelessWidget {
  const _RecipientSection({
    required this.enabled,
    required this.students,
    required this.coaches,
    required this.studentId,
    required this.coachId,
    required this.onStudentChanged,
    required this.onCoachChanged,
  });

  final bool enabled;
  final List<Student> students;
  final List<Coach> coaches;
  final String? studentId;
  final String? coachId;
  final ValueChanged<String?> onStudentChanged;
  final ValueChanged<String?> onCoachChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Recipient',
          icon: Icons.person_outline_rounded,
          trailing: enabled
              ? null
              : Text(
                  'Sale / Return only',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
        ),
        IgnorePointer(
          ignoring: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDropdownField<String?>(
                  label: 'Student',
                  value: studentId,
                  items: [
                    const DropdownMenuItem<String?>(child: Text('— None —')),
                    for (final s in students)
                      DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(s.fullName),
                      ),
                  ],
                  onChanged: enabled ? onStudentChanged : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppDropdownField<String?>(
                  label: 'Coach',
                  value: coachId,
                  items: [
                    const DropdownMenuItem<String?>(child: Text('— None —')),
                    for (final c in coaches)
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.fullName),
                      ),
                  ],
                  onChanged: enabled ? onCoachChanged : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
