import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/reports/data/report_builder.dart';

/// Lightweight ad-hoc report builder. The user picks an entity, columns,
/// filters, and an optional group-by; the result table is rendered below.
class ReportBuilderPage extends ConsumerStatefulWidget {
  const ReportBuilderPage({super.key});

  @override
  ConsumerState<ReportBuilderPage> createState() => _ReportBuilderPageState();
}

class _ReportBuilderPageState extends ConsumerState<ReportBuilderPage> {
  ReportEntity _entity = ReportEntity.students;
  Set<String> _selectedColumns = {};
  String? _groupBy;
  String? _orderBy;
  bool _descending = false;
  final _filters = <_FilterRow>[];

  ReportSpec? _spec;

  @override
  void initState() {
    super.initState();
    _selectedColumns = _entity.columns.take(5).map((c) => c.dbName).toSet();
  }

  void _resetForEntity(ReportEntity e) {
    setState(() {
      _entity = e;
      _selectedColumns = e.columns.take(5).map((c) => c.dbName).toSet();
      _groupBy = null;
      _orderBy = null;
      _filters.clear();
      _spec = null;
    });
  }

  void _run() {
    setState(() {
      _spec = ReportSpec(
        entity: _entity,
        columns: _selectedColumns.toList(),
        filters: [
          for (final f in _filters)
            if (f.column != null && f.value.trim().isNotEmpty)
              ReportFilter(column: f.column!, op: f.op, value: f.value),
        ],
        groupBy: _groupBy,
        orderBy: _orderBy,
        descending: _descending,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cols = _entity.columns;
    return Scaffold(
      appBar: AppBar(title: const Text('Custom report')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          DropdownButtonFormField<ReportEntity>(
            initialValue: _entity,
            decoration: const InputDecoration(labelText: 'Entity'),
            items: [
              for (final e in ReportEntity.values)
                DropdownMenuItem(value: e, child: Text(e.label)),
            ],
            onChanged: (v) => v == null ? null : _resetForEntity(v),
          ),
          const SizedBox(height: 12),
          Text('Columns', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in cols)
                FilterChip(
                  label: Text(c.label),
                  selected: _selectedColumns.contains(c.dbName),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _selectedColumns.add(c.dbName);
                    } else {
                      _selectedColumns.remove(c.dbName);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _orderBy,
                  decoration: const InputDecoration(labelText: 'Order by'),
                  items: [
                    const DropdownMenuItem<String?>(child: Text('— Default —')),
                    for (final c in cols)
                      DropdownMenuItem<String?>(
                          value: c.dbName, child: Text(c.label)),
                  ],
                  onChanged: (v) => setState(() => _orderBy = v),
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _descending,
                onChanged: (v) => setState(() => _descending = v),
              ),
              const Text('desc'),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _groupBy,
            decoration: const InputDecoration(
                labelText: 'Group by (returns counts)'),
            items: [
              const DropdownMenuItem<String?>(child: Text('— None —')),
              for (final c in cols)
                DropdownMenuItem<String?>(
                    value: c.dbName, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _groupBy = v),
          ),
          const SizedBox(height: 16),
          Text('Filters', style: Theme.of(context).textTheme.titleSmall),
          for (final f in _filters)
            _FilterEditor(row: f, columns: cols, onRemove: () {
              setState(() => _filters.remove(f));
            }, onChanged: () => setState(() {})),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add filter'),
            onPressed: () => setState(
              () => _filters.add(_FilterRow(column: cols.first.dbName)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run report'),
            onPressed: _selectedColumns.isEmpty ? null : _run,
          ),
          const SizedBox(height: 24),
          if (_spec != null) _ResultTable(spec: _spec!),
        ],
      ),
    );
  }
}

class _FilterRow {
  _FilterRow({this.column});
  String? column;
  String op = 'eq';
  String value = '';
}

class _FilterEditor extends StatefulWidget {
  const _FilterEditor({
    required this.row,
    required this.columns,
    required this.onRemove,
    required this.onChanged,
  });
  final _FilterRow row;
  final List<ReportColumn> columns;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends State<_FilterEditor> {
  late final _value =
      TextEditingController(text: widget.row.value);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: widget.row.column,
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final c in widget.columns)
                  DropdownMenuItem(value: c.dbName, child: Text(c.label)),
              ],
              onChanged: (v) {
                widget.row.column = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 90,
            child: DropdownButtonFormField<String>(
              initialValue: widget.row.op,
              decoration: const InputDecoration(isDense: true),
              items: const [
                DropdownMenuItem(value: 'eq', child: Text('=')),
                DropdownMenuItem(value: 'neq', child: Text('≠')),
                DropdownMenuItem(value: 'gt', child: Text('>')),
                DropdownMenuItem(value: 'gte', child: Text('≥')),
                DropdownMenuItem(value: 'lt', child: Text('<')),
                DropdownMenuItem(value: 'lte', child: Text('≤')),
                DropdownMenuItem(value: 'ilike', child: Text('contains')),
              ],
              onChanged: (v) {
                widget.row.op = v ?? 'eq';
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _value,
              decoration:
                  const InputDecoration(hintText: 'value', isDense: true),
              onChanged: (v) => widget.row.value = v,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}

class _ResultTable extends ConsumerWidget {
  const _ResultTable({required this.spec});
  final ReportSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportRunnerProvider(spec));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (rows) {
        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No rows'),
          );
        }
        final cols = rows.first.keys.toList();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final c in cols)
                    DataColumn(label: Text(c, overflow: TextOverflow.ellipsis)),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      for (final c in cols) DataCell(Text('${r[c] ?? ''}')),
                    ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
