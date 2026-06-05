import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class VendorsPage extends ConsumerWidget {
  const VendorsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vendorsProvider);
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
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New vendor'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _VendorSheet(),
        ),
      ),
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
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final v = rows[i];
                return AppListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: Text(v.name),
                  subtitle: Text([
                    if (v.contactName != null && v.contactName!.isNotEmpty)
                      v.contactName!,
                    if (v.phone != null && v.phone!.isNotEmpty) v.phone!,
                    if (v.email != null && v.email!.isNotEmpty) v.email!,
                  ].join(' · ')),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _VendorSheet(existing: v),
                  ),
                );
              },
            ),
          );
        },
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
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _contact, _email, _phone, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
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
            widget.existing == null ? 'New vendor' : 'Edit vendor',
            style: Theme.of(context).textTheme.titleLarge,
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
        ],
      ),
    );
  }
}
