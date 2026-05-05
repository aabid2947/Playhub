import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/features/centers/data/center.dart';
import 'package:playhub/features/centers/data/center_providers.dart'
    show createCenter, deactivateCenter, reactivateCenter, updateCenter;

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
  String? _error;

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
    setState(() {
      _busy = true;
      _error = null;
    });
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
      if (mounted) context.pop();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit center' : 'New center')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'City'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
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
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.archive_outlined, color: Colors.red),
                  label: const Text(
                    'Deactivate center',
                    style: TextStyle(color: Colors.red),
                  ),
                  onPressed: _busy ? null : _confirmDeactivate,
                ),
              ],
              if (isEdit && !widget.existing!.isActive) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.unarchive_outlined),
                  label: const Text('Reactivate center'),
                  onPressed: _busy ? null : _reactivate,
                ),
              ],
            ],
          ),
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
      if (mounted) context.pop();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reactivate() async {
    setState(() => _busy = true);
    try {
      await reactivateCenter(ref, widget.existing!.id);
      if (mounted) context.pop();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
