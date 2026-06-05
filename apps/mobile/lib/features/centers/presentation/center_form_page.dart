import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/centers/data/center.dart';
import 'package:playhub/features/centers/data/center_providers.dart'
    show createCenter, deactivateCenter, reactivateCenter, updateCenter;
import 'package:playhub/shared/widgets/widgets.dart';

class CenterFormPage extends ConsumerStatefulWidget {
  const CenterFormPage({super.key, this.existing});

  final Centre? existing;

  @override
  ConsumerState<CenterFormPage> createState() => _CenterFormPageState();
}

class _CenterFormPageState extends ConsumerState<CenterFormPage> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      };
      if (isEdit) {
        await updateCenter(ref, widget.existing!.id, patch);
      } else {
        await createCenter(ref, patch);
      }
      if (!mounted) return;
      AppSnackbar.success(context, isEdit ? 'Center updated.' : 'Center created.');
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final danger = AppSemanticColors.of(context).danger;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit center' : 'New center')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const AppSectionHeader(title: 'Center details'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _name,
              label: 'Name *',
              hint: 'e.g. North Campus',
              prefixIcon: const Icon(Icons.location_city_outlined),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _address,
              label: 'Address',
              hint: 'Street, area',
              prefixIcon: const Icon(Icons.home_outlined),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _city,
              label: 'City',
              prefixIcon: const Icon(Icons.map_outlined),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _phone,
              label: 'Phone',
              hint: '+91 …',
              prefixIcon: const Icon(Icons.call_outlined),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _busy ? null : _save(),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save changes' : 'Create center'),
            ),
            if (isEdit && widget.existing!.isActive) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                icon: Icon(Icons.archive_outlined, color: danger),
                label: Text(
                  'Deactivate center',
                  style: TextStyle(color: danger),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: danger.withValues(alpha: 0.5)),
                ),
                onPressed: _busy ? null : _confirmDeactivate,
              ),
            ],
            if (isEdit && !widget.existing!.isActive) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                icon: const Icon(Icons.unarchive_outlined),
                label: const Text('Reactivate center'),
                onPressed: _busy ? null : _reactivate,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate this center?'),
        content: const Text(
          'It will be hidden from new assignments. Existing batches and '
          'students stay linked. You can reactivate later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await deactivateCenter(ref, widget.existing!.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Center deactivated.');
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reactivate() async {
    setState(() => _busy = true);
    try {
      await reactivateCenter(ref, widget.existing!.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Center reactivated.');
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
