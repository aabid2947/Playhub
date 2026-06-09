import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Vendor directory — v1 "Sports-Light" list archetype (B). Pushed page (keeps
/// its own AppBar) that also renders as the third tab body inside the inventory
/// landing. Each supplier is an [AppCard] tile with a tinted store icon,
/// a one-line contact subtitle, and an active-status [AppBadge]. Create/edit go
/// through a scrollable titled bottom sheet that calls `upsertVendor`.
class VendorsPage extends ConsumerWidget {
  const VendorsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vendorsProvider);
    final caps = ref.watch(capabilitiesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendors'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(vendorsProvider),
          ),
        ],
      ),
      floatingActionButton: caps.manageInventory
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New vendor'),
              tooltip: 'Add a vendor',
              onPressed: () => _openSheet(context),
            )
          : null,
      body: async.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(vendorsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const AppEmptyState(
              icon: Icons.storefront_outlined,
              title: 'No vendors yet',
              subtitle: 'Add suppliers to track where equipment comes from.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vendorsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              // +1 leading row for the in-body result-count header.
              itemCount: rows.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) return _CountHeader(count: rows.length);
                return _VendorCard(vendor: rows[i - 1]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// Opens the create/edit sheet. Scrollable + keyboard-safe so the fields never
/// clip behind the on-screen keyboard.
void _openSheet(BuildContext context, {Vendor? existing}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VendorSheet(existing: existing),
  );
}

/// In-body header: a neutral count [AppBadge] standing in for the list count
/// (this is a pushed page / tab body, so the count lives in the body, not a bar).
class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final noun = count == 1 ? 'vendor' : 'vendors';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppBadge(
          text: '$count $noun',
          icon: Icons.storefront_outlined,
        ),
      ),
    );
  }
}

/// A v1 list tile rendered as an [AppCard]: a tinted store icon, the vendor
/// name, a one-line contact subtitle, and a trailing status [AppBadge]
/// ("Active" success / "Inactive" neutral). Tapping opens the edit sheet.
class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Active vendors carry the brand tint; inactive ones read muted.
    final tint = vendor.isActive ? scheme.primary : scheme.onSurfaceVariant;

    // Subtitle is one tight line of whatever contact details exist.
    final contact = [
      if (vendor.contactName != null && vendor.contactName!.isNotEmpty)
        vendor.contactName!,
      if (vendor.phone != null && vendor.phone!.isNotEmpty) vendor.phone!,
      if (vendor.email != null && vendor.email!.isNotEmpty) vendor.email!,
    ].join(' · ');

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      onTap: () => _openSheet(context, existing: vendor),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.store_outlined, color: tint, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vendor.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: AppType.semibold),
                ),
                const SizedBox(height: 2),
                Text(
                  contact.isEmpty ? 'No contact details' : contact,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppBadge(
            text: vendor.isActive ? 'Active' : 'Inactive',
            tone:
                vendor.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
          ),
        ],
      ),
    );
  }
}

class _VendorSheet extends ConsumerStatefulWidget {
  const _VendorSheet({this.existing});
  final Vendor? existing;

  @override
  ConsumerState<_VendorSheet> createState() => _VendorSheetState();
}

class _VendorSheetState extends ConsumerState<_VendorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _contact =
      TextEditingController(text: widget.existing?.contactName ?? '');
  late final _email =
      TextEditingController(text: widget.existing?.email ?? '');
  late final _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late bool _isActive = widget.existing?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _contact, _email, _phone, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Hard-delete the vendor after confirmation. RLS limits this to center_admin
  /// and above; `manageInventory` mirrors that on the UI. Items/movements that
  /// referenced it keep their row (FK set-null).
  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete "${existing.name}"?',
      message:
          'This permanently removes the vendor. Items and stock movements that '
          'referenced it stay, just unlinked. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(inventoryRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.deleteVendor(existing.id);
      ref.invalidate(vendorsProvider);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(inventoryRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.upsertVendor(
        id: widget.existing?.id,
        name: _name.text.trim(),
        contactName:
            _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        address:
            _address.text.trim().isEmpty ? null : _address.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        isActive: _isActive,
      );
      ref.invalidate(vendorsProvider);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final caps = ref.watch(capabilitiesProvider);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg + viewInsets,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle anchors the scrollable sheet.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.existing == null ? 'New vendor' : 'Edit vendor',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppFormField(
                controller: _name,
                label: 'Name *',
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _contact,
                label: 'Contact name',
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppFormField(
                      controller: _phone,
                      label: 'Phone',
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppFormField(
                      controller: _email,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _address,
                label: 'Address',
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormField(
                controller: _notes,
                label: 'Notes',
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _isActive = v),
                title: Text('Active', style: theme.textTheme.bodyLarge),
                subtitle: Text(
                  'Inactive vendors stay on record but are hidden from pickers.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
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
              if (widget.existing != null && caps.manageInventory) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  icon: Icon(
                    Icons.delete_outline,
                    color: AppSemanticColors.of(context).danger,
                  ),
                  label: Text(
                    'Delete vendor',
                    style: TextStyle(
                      color: AppSemanticColors.of(context).danger,
                    ),
                  ),
                  onPressed: _saving ? null : _confirmDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
