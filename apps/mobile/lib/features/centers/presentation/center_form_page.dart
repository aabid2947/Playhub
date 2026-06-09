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
  late final _state = TextEditingController(text: widget.existing?.state ?? '');
  late final _pincode =
      TextEditingController(text: widget.existing?.pincode ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'address': _nullIfEmpty(_address.text),
        'city': _nullIfEmpty(_city.text),
        'state': _nullIfEmpty(_state.text),
        'pincode': _nullIfEmpty(_pincode.text),
        'phone': _nullIfEmpty(_phone.text),
        'email': _nullIfEmpty(_email.text),
      };
      if (isEdit) {
        await updateCenter(ref, widget.existing!.id, patch);
      } else {
        await createCenter(ref, patch);
      }
      if (!mounted) return;
      AppSnackbar.success(
        context,
        isEdit ? 'Center updated.' : 'Center created.',
      );
      context.pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit center' : 'New center')),
      // Pinned, full-width primary action (archetype D) — inline spinner while
      // saving. A floating shadow lifts the bar off the scrolling form below it.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: AppShadows.floating,
        ),
        child: SafeArea(
          minimum: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _busy
                    ? 'Saving…'
                    : (isEdit ? 'Save changes' : 'Create center'),
              ),
              onPressed: _busy ? null : _save,
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Identity ------------------------------------------------------
            const AppSectionHeader(
              title: 'Identity',
              icon: Icons.location_city_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _name,
              label: 'Name *',
              hint: 'e.g. North Campus',
              prefixIcon: const Icon(Icons.location_city_outlined),
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),

            // Contact -------------------------------------------------------
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(
              title: 'Contact',
              icon: Icons.call_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _phone,
              label: 'Phone',
              hint: '+91 …',
              prefixIcon: const Icon(Icons.call_outlined),
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _email,
              label: 'Email',
              hint: 'center@academy.in',
              prefixIcon: const Icon(Icons.mail_outline),
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),

            // Address -------------------------------------------------------
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(
              title: 'Address',
              icon: Icons.place_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _address,
              label: 'Street address',
              hint: 'Street, area',
              prefixIcon: const Icon(Icons.home_outlined),
              enabled: !_busy,
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            // City + State stack gracefully on narrow widths.
            LayoutBuilder(
              builder: (context, constraints) {
                final city = AppFormField(
                  controller: _city,
                  label: 'City',
                  prefixIcon: const Icon(Icons.map_outlined),
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                );
                final state = AppFormField(
                  controller: _state,
                  label: 'State',
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                );
                if (constraints.maxWidth < 360) {
                  return Column(
                    children: [
                      city,
                      const SizedBox(height: AppSpacing.md),
                      state,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: city),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: state),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _pincode,
              label: 'Pincode',
              hint: '6-digit PIN',
              prefixIcon: const Icon(Icons.markunread_mailbox_outlined),
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _busy ? null : _save(),
            ),

            // Lifecycle (edit-only, clearly separated below a divider). The
            // primary save action is pinned at the bottom (see bottomNavigationBar);
            // this lifecycle action stays a distinct, secondary edit-only path.
            if (isEdit) ...[
              const SizedBox(height: AppSpacing.xl),
              Divider(color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: AppSpacing.md),
              const AppSectionHeader(
                title: 'Center status',
                icon: Icons.toggle_on_outlined,
              ),
              const SizedBox(height: AppSpacing.sm),
              _LifecycleCard(
                isActive: widget.existing!.isActive,
                busy: _busy,
                onDeactivate: _confirmDeactivate,
                onReactivate: _reactivate,
              ),
            ],
            // Tail spacing so the last field clears the pinned save bar.
            const SizedBox(height: AppSpacing.xl),
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

/// Edit-only card that surfaces the center's active/inactive state as a badge
/// and offers the matching lifecycle action, kept visually distinct from the
/// editable fields above.
class _LifecycleCard extends StatelessWidget {
  const _LifecycleCard({
    required this.isActive,
    required this.busy,
    required this.onDeactivate,
    required this.onReactivate,
  });

  final bool isActive;
  final bool busy;
  final Future<void> Function() onDeactivate;
  final Future<void> Function() onReactivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = AppSemanticColors.of(context).danger;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isActive ? 'This center is active.' : 'This center is inactive.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppBadge(
                text: isActive ? 'Active' : 'Inactive',
                tone: isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isActive
                ? 'Deactivating hides it from new assignments. Existing batches '
                    'and students stay linked.'
                : 'Reactivating makes it available for new assignments again.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: isActive
                ? OutlinedButton.icon(
                    icon: Icon(Icons.archive_outlined, color: danger),
                    label: Text(
                      'Deactivate center',
                      style: TextStyle(color: danger),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: danger.withValues(alpha: 0.5)),
                    ),
                    onPressed: busy ? null : onDeactivate,
                  )
                : OutlinedButton.icon(
                    icon: const Icon(Icons.unarchive_outlined),
                    label: const Text('Reactivate center'),
                    onPressed: busy ? null : onReactivate,
                  ),
          ),
        ],
      ),
    );
  }
}
