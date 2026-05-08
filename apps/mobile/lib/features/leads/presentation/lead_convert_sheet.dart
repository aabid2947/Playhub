import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';

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
  String? _error;

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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(leadsRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.convert(
        leadId: widget.lead.id,
        batchId: _batchId,
      );
      ref.invalidate(leadByIdProvider(widget.lead.id));
      ref.invalidate(leadActivitiesProvider(widget.lead.id));
      ref.invalidate(leadsListProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Convert ${widget.lead.displayName}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Creates a student record from the lead, optionally enrolling '
            'them into a batch.',
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<({String id, String name})>>(
            future: _loadBatches(),
            builder: (_, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return DropdownButtonFormField<String?>(
                initialValue: _batchId,
                decoration: const InputDecoration(
                  labelText: 'Initial batch (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('No initial batch')),
                  for (final b in snap.data!)
                    DropdownMenuItem<String?>(
                        value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => _batchId = v),
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
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
