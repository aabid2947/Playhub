import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Bottom sheet to convert a lead → student. Optionally enrolls into a
/// batch and links a parent user. Calls the convert-lead-to-student
/// Edge Function which wraps the convert_lead RPC.
class LeadConvertSheet extends ConsumerStatefulWidget {
  const LeadConvertSheet({required this.lead, super.key});
  final Lead lead;

  @override
  ConsumerState<LeadConvertSheet> createState() => _LeadConvertSheetState();
}

class _LeadConvertSheetState extends ConsumerState<LeadConvertSheet> {
  String? _batchId;
  bool _busy = false;
  // Built once — keeping it out of build() avoids re-querying (and flickering
  // the dropdown back to a spinner) on every setState.
  late final Future<List<({String id, String name})>> _batchesFuture =
      _loadBatches();

  Future<List<({String id, String name})>> _loadBatches() async {
    final client = ref.read(supabaseClientProvider);
    final rows = await client
        .from('batches')
        .select('id, name')
        .eq('academy_id', widget.lead.academyId)
        .eq('is_active', true)
        .order('name');
    return [
      for (final r in rows as List)
        (id: (r as Map)['id'] as String, name: r['name'] as String),
    ];
  }

  Future<void> _convert() async {
    setState(() => _busy = true);
    try {
      final repo = await ref.read(leadsRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.convert(
        leadId: widget.lead.id,
        batchId: _batchId,
      );
      ref
        ..invalidate(leadByIdProvider(widget.lead.id))
        ..invalidate(leadActivitiesProvider(widget.lead.id))
        ..invalidate(leadsListProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Lead converted to student.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Convert ${widget.lead.displayName}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Creates a student record from the lead, optionally enrolling '
            'them into a batch.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FutureBuilder<List<({String id, String name})>>(
            future: _batchesFuture,
            builder: (_, snap) {
              if (!snap.hasData) {
                return const SizedBox(height: 48, child: AppLoading());
              }
              return AppDropdownField<String?>(
                label: 'Initial batch (optional)',
                value: _batchId,
                items: [
                  const DropdownMenuItem<String?>(
                      child: Text('No initial batch')),
                  for (final b in snap.data!)
                    DropdownMenuItem<String?>(
                        value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => _batchId = v),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(_busy ? 'Converting…' : 'Convert'),
                onPressed: _busy ? null : _convert,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
