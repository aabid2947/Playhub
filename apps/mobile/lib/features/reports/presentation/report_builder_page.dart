import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/reports/data/report_builder.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Lightweight ad-hoc report builder. The user works top-to-bottom — pick an
/// entity, choose columns, add filters, set group/order — then runs the report
/// and reads the result rows below.
///
/// v1 "Sports-Light", archetype C (pushed builder): a navy analytics hero with
/// a back button anchors the top, the builder body overlaps it upward, and each
/// step is an [AppCard] section under an [AppSectionHeader]. The field / filter /
/// group-by logic and the [reportRunnerProvider] run are unchanged.
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

  /// Human label for a db column within the active entity (falls back to the
  /// raw db name for derived columns like `count`).
  String _labelFor(String dbName) {
    for (final c in _entity.columns) {
      if (c.dbName == dbName) return c.label;
    }
    return dbName;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cols = _entity.columns;
    final selectedCount = _selectedColumns.length;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Navy analytics hero with the back button + a live summary chip.
          AppGradientHeader(
            colors: AppPalette.navyGradient,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppCircleIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Custom report',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: AppType.heavy,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Pick an entity, choose columns, add filters, then run.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    AppGlassChip(_entity.label, icon: Icons.dataset_outlined),
                    AppGlassChip(
                      '$selectedCount of ${cols.length} columns',
                      icon: Icons.view_column_outlined,
                    ),
                    if (_filters.isNotEmpty)
                      AppGlassChip(
                        '${_filters.length} '
                        '${_filters.length == 1 ? 'filter' : 'filters'}',
                        icon: Icons.filter_alt_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Body overlaps the hero band upward, v1-style.
          Transform.translate(
            offset: const Offset(0, -AppSpacing.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Entity ------------------------------------------------
                  const AppSectionHeader(
                    title: 'Report on',
                    icon: Icons.dataset_outlined,
                  ),
                  AppCard(
                    child: AppDropdownField<ReportEntity>(
                      label: 'Entity',
                      value: _entity,
                      items: [
                        for (final e in ReportEntity.values)
                          DropdownMenuItem(value: e, child: Text(e.label)),
                      ],
                      onChanged: (v) => v == null ? null : _resetForEntity(v),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // 2. Columns -----------------------------------------------
                  AppSectionHeader(
                    title: 'Columns',
                    icon: Icons.view_column_outlined,
                    trailing: Text(
                      '$selectedCount of ${cols.length} selected',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
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
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => setState(
                                () => _selectedColumns =
                                    cols.map((c) => c.dbName).toSet(),
                              ),
                              child: const Text('Select all'),
                            ),
                            TextButton(
                              onPressed: selectedCount == 0
                                  ? null
                                  : () => setState(_selectedColumns.clear),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // 3. Filters -----------------------------------------------
                  const AppSectionHeader(
                    title: 'Filters',
                    icon: Icons.filter_alt_outlined,
                  ),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_filters.isEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Text(
                              'No filters — the report returns all rows you '
                              'can access.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        for (final f in _filters)
                          _FilterEditor(
                            row: f,
                            columns: cols,
                            onRemove: () => setState(() => _filters.remove(f)),
                            onChanged: () => setState(() {}),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add filter'),
                            onPressed: () => setState(
                              () => _filters
                                  .add(_FilterRow(column: cols.first.dbName)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // 4. Group / Order -----------------------------------------
                  const AppSectionHeader(
                    title: 'Group & order',
                    icon: Icons.sort_rounded,
                  ),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppDropdownField<String?>(
                          label: 'Group by',
                          hint: '— None —',
                          value: _groupBy,
                          items: [
                            const DropdownMenuItem<String?>(
                              child: Text('— None —'),
                            ),
                            for (final c in cols)
                              DropdownMenuItem<String?>(
                                value: c.dbName,
                                child: Text(c.label),
                              ),
                          ],
                          onChanged: (v) => setState(() => _groupBy = v),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppDropdownField<String?>(
                          label: 'Order by',
                          hint: '— Default —',
                          value: _orderBy,
                          items: [
                            const DropdownMenuItem<String?>(
                              child: Text('— Default —'),
                            ),
                            for (final c in cols)
                              DropdownMenuItem<String?>(
                                value: c.dbName,
                                child: Text(c.label),
                              ),
                          ],
                          onChanged: (v) => setState(() => _orderBy = v),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Descending order'),
                          value: _descending,
                          onChanged: (v) => setState(() => _descending = v),
                        ),
                        Text(
                          _groupBy == null
                              ? 'Rows are sorted by the order-by column.'
                              : 'Grouping by ${_labelFor(_groupBy!)} returns a '
                                  'count per distinct value.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // 5. Run ---------------------------------------------------
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Run report'),
                      onPressed: _selectedColumns.isEmpty ? null : _run,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // 6. Results -----------------------------------------------
                  if (_spec != null)
                    _ResultsView(spec: _spec!, labelFor: _labelFor),
                ],
              ),
            ),
          ),
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

/// One filter row. Lays the column + operator side-by-side, with the value
/// field and remove action below, so the row stacks readably on a phone.
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
  late final _value = TextEditingController(text: widget.row.value);

  static const _ops = <(String, String)>[
    ('eq', '='),
    ('neq', '≠'),
    ('gt', '>'),
    ('gte', '≥'),
    ('lt', '<'),
    ('lte', '≤'),
    ('ilike', 'contains'),
  ];

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: AppDropdownField<String>(
                  label: 'Column',
                  value: widget.row.column,
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
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: AppDropdownField<String>(
                  label: 'Operator',
                  value: widget.row.op,
                  items: [
                    for (final op in _ops)
                      DropdownMenuItem(value: op.$1, child: Text(op.$2)),
                  ],
                  onChanged: (v) {
                    widget.row.op = v ?? 'eq';
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppFormField(
                  controller: _value,
                  label: 'Value',
                  hint: 'Value to match',
                  onChanged: (v) => widget.row.value = v,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove filter',
                onPressed: widget.onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders the run result as phone-readable cards (one card per row, each a
/// stack of column → value pairs) with a row-count header.
class _ResultsView extends ConsumerWidget {
  const _ResultsView({required this.spec, required this.labelFor});

  final ReportSpec spec;
  final String Function(String) labelFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(reportRunnerProvider(spec));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: AppLoading(label: 'Running report…'),
      ),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(reportRunnerProvider(spec)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const AppEmptyState(
            icon: Icons.table_chart_outlined,
            title: 'No rows',
            subtitle: 'No records match this report. Adjust the filters and '
                'run again.',
          );
        }
        final cols = rows.first.keys.toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              title: 'Results',
              icon: Icons.table_chart_outlined,
              trailing: AppBadge(
                text: '${rows.length} ${rows.length == 1 ? 'row' : 'rows'}',
                tone: AppBadgeTone.info,
              ),
            ),
            for (final r in rows) ...[
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cols.length; i++) ...[
                      if (i != 0)
                        Divider(
                          height: AppSpacing.md,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              labelFor(cols[i]),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                letterSpacing: AppType.trackingWide,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '${r[cols[i]] ?? '—'}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}
