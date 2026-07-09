// `_rows` is nullable until the user picks a file; the lint would prefer
// `late` non-nullable but that's wrong for this state machine.
// ignore_for_file: use_late_for_private_fields_and_variables

import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Required CSV header columns.
const _requiredCols = ['first_name', 'last_name'];

/// All recognised CSV columns. Anything else is ignored.
const _allCols = [
  'first_name',
  'last_name',
  'email',
  'phone',
  'specialization', // pipe-separated within the cell, e.g. "Cricket|Batting"
  'experience_years',
  'qualifications',
  'salary',
  'payment_type',
];

/// Columns that accept several values in one cell, separated by a pipe (`|`).
const _multiValueCols = ['specialization', 'qualifications'];

const _templateCsv =
    'first_name,last_name,email,phone,specialization,experience_years,qualifications,salary,payment_type\n'
    'Rohit,Verma,rohit@example.com,9876543220,Cricket|Batting,5,BPEd,30000,monthly\n'
    'Anjali,Nair,anjali@example.com,9876543221,Badminton,3,NIS Level 1,500,session\n';

/// A single row failure surfaced in the results report.
class _RowFailure {
  const _RowFailure(this.rowNumber, this.message);

  /// 1-based row number as it appears in the CSV (header excluded).
  final int rowNumber;
  final String message;
}

class CoachBulkImportPage extends ConsumerStatefulWidget {
  const CoachBulkImportPage({super.key});

  @override
  ConsumerState<CoachBulkImportPage> createState() =>
      _CoachBulkImportPageState();
}

class _CoachBulkImportPageState extends ConsumerState<CoachBulkImportPage> {
  List<Map<String, String>>? _rows;
  String? _error;
  String? _filename;
  // Required target center + sports applied to EVERY imported coach.
  // coaches.center_id is NOT NULL at the DB (20260710000000); ">=1 sport" is a
  // product rule (coach_sports has no DB cardinality constraint) enforced here.
  String? _centerId;
  final Set<String> _sportIds = <String>{};
  bool _busy = false;
  int? _imported;
  int? _failed;
  int _processed = 0;
  int _total = 0;
  final List<_RowFailure> _failures = [];

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (res == null || res.files.isEmpty) return;
    final file = res.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Empty file');
      return;
    }
    try {
      final text = utf8.decode(bytes);
      final parsed = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
          .convert(text);
      if (parsed.isEmpty) {
        setState(() => _error = 'CSV is empty');
        return;
      }
      final headers = parsed.first.map((h) => h.toString().trim()).toList();
      for (final req in _requiredCols) {
        if (!headers.contains(req)) {
          setState(() => _error = 'Missing required column: $req');
          return;
        }
      }
      final rows = <Map<String, String>>[];
      for (var i = 1; i < parsed.length; i++) {
        final r = parsed[i];
        final m = <String, String>{};
        for (var j = 0; j < headers.length && j < r.length; j++) {
          final h = headers[j];
          if (!_allCols.contains(h)) continue;
          final v = r[j].toString().trim();
          if (v.isNotEmpty) m[h] = v;
        }
        rows.add(m);
      }
      setState(() {
        _rows = rows;
        _filename = file.name;
        _error = null;
        _imported = null;
        _failed = null;
        _failures.clear();
        _processed = 0;
        _total = 0;
      });
    } on Object catch (e) {
      setState(() => _error = 'Parse error: $e');
    }
  }

  bool _isValid(Map<String, String> r) {
    for (final c in _requiredCols) {
      if ((r[c] ?? '').isEmpty) return false;
    }
    return true;
  }

  /// The required columns that are missing from [r], for inline reporting.
  List<String> _missingRequired(Map<String, String> r) =>
      [for (final c in _requiredCols) if ((r[c] ?? '').isEmpty) c];

  List<String> _splitPipe(String s) =>
      s.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null) return;
    setState(() {
      _busy = true;
      _imported = null;
      _failed = null;
      _error = null;
      _failures.clear();
      _processed = 0;
      _total = rows.length;
    });

    final profile = await ref.read(currentProfileProvider.future);
    final academyId = profile?.academyId;
    if (academyId == null) {
      setState(() {
        _busy = false;
        _error = 'No academy linked to current user';
      });
      return;
    }

    final centerId = _centerId;
    if (centerId == null) {
      setState(() {
        _busy = false;
        _error = 'Pick a center to import coaches into.';
      });
      return;
    }
    if (_sportIds.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Select at least one sport for the imported coaches.';
      });
      return;
    }
    final sportIds = _sportIds.toList();
    final sportsRepo = await ref.read(sportsRepoProvider.future);

    final client = ref.read(supabaseClientProvider);
    var ok = 0;
    var fail = 0;
    final failures = <_RowFailure>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      // 1-based CSV row number (data rows start after the header).
      final rowNumber = i + 1;
      if (!_isValid(r)) {
        fail++;
        failures.add(
          _RowFailure(
            rowNumber,
            'Missing required: ${_missingRequired(r).join(', ')}',
          ),
        );
        if (mounted) setState(() => _processed = i + 1);
        continue;
      }
      try {
        final inserted = await client.from('coaches').insert({
          'academy_id': academyId,
          'center_id': centerId,
          'first_name': r['first_name'],
          'last_name': r['last_name'],
          if (r['email'] != null) 'email': r['email'],
          if (r['phone'] != null) 'phone': r['phone'],
          if (r['specialization'] != null)
            'specialization': _splitPipe(r['specialization']!),
          if (r['qualifications'] != null)
            'qualifications': _splitPipe(r['qualifications']!),
          if (r['experience_years'] != null)
            'experience_years': int.tryParse(r['experience_years']!),
          if (r['salary'] != null) 'salary': double.tryParse(r['salary']!),
          if (r['payment_type'] != null) 'payment_type': r['payment_type'],
        }).select('id').single();
        // Every coach needs >=1 sport (head_coach scoping + the perf rubric
        // depend on it). Tag all imported coaches with the chosen sports.
        await sportsRepo?.setCoachSports(inserted['id'] as String, sportIds);
        ok++;
      } on Object catch (e) {
        fail++;
        failures.add(_RowFailure(rowNumber, friendlyError(e)));
      }
      if (mounted) setState(() => _processed = i + 1);
    }
    ref.invalidate(coachesProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _imported = ok;
      _failed = fail;
      _failures
        ..clear()
        ..addAll(failures);
    });
  }

  Future<void> _showTemplate() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV template'),
        content: const SizedBox(
          width: 600,
          child: SelectableText(
            _templateCsv,
            style: TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    final validCount = rows == null ? 0 : rows.where(_isValid).length;
    final invalidCount = rows == null ? 0 : rows.length - validCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import coaches'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.help_outline),
            label: const Text('Template'),
            onPressed: _showTemplate,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── Step 1 — Template ─────────────────────────────────────────
          _StepCard(
            step: 1,
            title: 'Prepare your CSV',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your file needs a header row. These columns are required:',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                const _ColumnChips(
                  columns: _requiredCols,
                  tone: AppBadgeTone.brand,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Optional columns (filled in when present):',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                _ColumnChips(
                  columns:
                      _allCols.where((c) => !_requiredCols.contains(c)).toList(),
                  multiValue: _multiValueCols,
                  tone: AppBadgeTone.neutral,
                ),
                const SizedBox(height: AppSpacing.md),
                const _MultiValueNote(columns: _multiValueCols),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('View template'),
                    onPressed: _showTemplate,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Step 2 — Pick & preview ───────────────────────────────────
          _StepCard(
            step: 2,
            title: 'Pick & preview',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(_filename == null ? 'Pick CSV' : 'Choose another'),
                      onPressed: _busy ? null : _pick,
                    ),
                    if (_filename != null) ...[
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          _filename!,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _InlineError(message: _error!),
                ],
                if (rows != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _PreviewSummary(
                    total: rows.length,
                    valid: validCount,
                    invalid: invalidCount,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (rows.isEmpty)
                    Text(
                      'No data rows found below the header.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    _PreviewList(
                      rows: rows,
                      isValid: _isValid,
                      missingRequired: _missingRequired,
                      splitPipe: _splitPipe,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Step 3 — Import & results ─────────────────────────────────
          _StepCard(
            step: 3,
            title: 'Import & results',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rows == null)
                  Text(
                    'Pick a file above to enable importing.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  _CenterSelect(
                    value: _centerId,
                    onChanged: (v) => setState(() => _centerId = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SportSelect(
                    selectedIds: _sportIds,
                    onToggle: (sid, sel) => setState(() {
                      if (sel) {
                        _sportIds.add(sid);
                      } else {
                        _sportIds.remove(sid);
                      }
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text('Import $validCount valid rows'),
                      onPressed: (_busy ||
                              validCount == 0 ||
                              _centerId == null ||
                              _sportIds.isEmpty)
                          ? null
                          : _import,
                    ),
                  ),
                  if (_centerId == null || _sportIds.isEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Pick a center and at least one sport above to enable '
                      'importing.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (invalidCount > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '$invalidCount invalid row(s) will be skipped.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ImportProgress(processed: _processed, total: _total),
                  ],
                ],
                if (_imported != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ResultSummary(
                    imported: _imported!,
                    failed: _failed ?? 0,
                    failures: _failures,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Required target-center dropdown applied to the whole import (coaches.center_id
/// is NOT NULL at the DB). Blocks with guidance when the academy has no center.
class _CenterSelect extends ConsumerWidget {
  const _CenterSelect({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(centersProvider).when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => _InlineError(message: friendlyError(e)),
          data: (centres) {
            final active = centres.where((c) => c.isActive).toList();
            if (active.isEmpty) {
              return const _InlineError(
                message: 'Create a center first — imported coaches must '
                    'belong to a center.',
              );
            }
            return AppDropdownField<String>(
              label: 'Import all coaches into center *',
              value: value,
              items: [
                for (final c in active)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: onChanged,
            );
          },
        );
  }
}

/// Multi-select of the academy's enabled sports, applied to every imported
/// coach. Deduped by catalog sport id (a sport may be enabled at many centers).
/// Blocks with guidance when no sport is enabled (every coach needs >=1 sport).
class _SportSelect extends ConsumerWidget {
  const _SportSelect({required this.selectedIds, required this.onToggle});

  final Set<String> selectedIds;
  final void Function(String sportId, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(academyCenterSportsProvider).when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => _InlineError(message: friendlyError(e)),
          data: (list) {
            final byId = <String, String>{};
            for (final cs in list) {
              byId.putIfAbsent(cs.sport.id, () => cs.sport.name);
            }
            if (byId.isEmpty) {
              return const _InlineError(
                message: 'Enable a sport first (Settings → Sports) — every '
                    'imported coach must have at least one sport.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sports for all imported coaches *',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final e in byId.entries)
                      FilterChip(
                        label: Text(e.value),
                        selected: selectedIds.contains(e.key),
                        onSelected: (sel) => onToggle(e.key, sel),
                      ),
                  ],
                ),
              ],
            );
          },
        );
  }
}

/// A numbered step container: a leading step number, a title, then content.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.child,
  });

  final int step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$step',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: AppType.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// A wrap of column-name pills. Columns listed in [multiValue] get a trailing
/// `|` marker so the pipe-separated convention is visible at a glance.
class _ColumnChips extends StatelessWidget {
  const _ColumnChips({
    required this.columns,
    required this.tone,
    this.multiValue = const [],
  });

  final List<String> columns;
  final AppBadgeTone tone;
  final List<String> multiValue;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final c in columns)
          AppBadge(
            text: multiValue.contains(c) ? '$c  a|b' : c,
            tone: tone,
          ),
      ],
    );
  }
}

/// Explains the pipe (`|`) multi-value convention with a worked example.
class _MultiValueNote extends StatelessWidget {
  const _MultiValueNote({required this.columns});

  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      const TextSpan(text: 'Some columns ('),
                      TextSpan(
                        text: columns.join(', '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: AppType.semibold,
                        ),
                      ),
                      const TextSpan(
                        text: ') can hold several values in one cell. '
                            'Separate them with a pipe — do not add spaces or '
                            'extra commas.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Example:  Cricket|Batting  →  Cricket, Batting',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline danger strip for parse / validation errors.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sem = AppSemanticColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: sem.dangerContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: sem.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: sem.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// Total / valid / invalid counts for the picked file.
class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({
    required this.total,
    required this.valid,
    required this.invalid,
  });

  final int total;
  final int valid;
  final int invalid;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppBadge(text: '$total rows'),
        AppBadge(text: '$valid valid', tone: AppBadgeTone.success),
        if (invalid > 0)
          AppBadge(text: '$invalid invalid', tone: AppBadgeTone.danger),
      ],
    );
  }
}

/// A readable, vertically-stacked preview. Each row is a compact card showing
/// its key fields; invalid rows are flagged inline with the missing columns.
class _PreviewList extends StatelessWidget {
  const _PreviewList({
    required this.rows,
    required this.isValid,
    required this.missingRequired,
    required this.splitPipe,
  });

  final List<Map<String, String>> rows;
  final bool Function(Map<String, String>) isValid;
  final List<String> Function(Map<String, String>) missingRequired;
  final List<String> Function(String) splitPipe;

  /// Cap the preview so a very large file doesn't build thousands of cards;
  /// the full set is still imported.
  static const _previewCap = 50;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = rows.length > _previewCap ? _previewCap : rows.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _PreviewRow(
              rowNumber: i + 1,
              row: rows[i],
              valid: isValid(rows[i]),
              missing: missingRequired(rows[i]),
              splitPipe: splitPipe,
            ),
          ),
        if (rows.length > shown)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '+ ${rows.length - shown} more row(s) — all will be imported.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.rowNumber,
    required this.row,
    required this.valid,
    required this.missing,
    required this.splitPipe,
  });

  final int rowNumber;
  final Map<String, String> row;
  final bool valid;
  final List<String> missing;
  final List<String> Function(String) splitPipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);

    final name = [row['first_name'], row['last_name']]
        .where((v) => v != null && v.isNotEmpty)
        .join(' ');
    final secondary = [
      if ((row['experience_years'] ?? '').isNotEmpty)
        '${row['experience_years']} yr',
      if ((row['payment_type'] ?? '').isNotEmpty) row['payment_type'],
      if ((row['email'] ?? '').isNotEmpty) row['email'],
      if ((row['phone'] ?? '').isNotEmpty) row['phone'],
    ].whereType<String>().join(' · ');

    // Multi-value cells are shown as parsed chips so the user sees exactly how
    // the pipe-separated text will land in the database.
    final specialization = splitPipe(row['specialization'] ?? '');
    final qualifications = splitPipe(row['qualifications'] ?? '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: valid ? scheme.surfaceContainerHighest : sem.dangerContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: valid ? scheme.outlineVariant : sem.danger,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rowNumber',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: AppType.semibold,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '(no name)' : name,
                  style: theme.textTheme.bodyLarge,
                ),
                if (secondary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    secondary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (specialization.isNotEmpty || qualifications.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final s in specialization)
                        AppBadge(text: s, tone: AppBadgeTone.info),
                      for (final q in qualifications)
                        AppBadge(text: q),
                    ],
                  ),
                ],
                if (!valid) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Missing: ${missing.join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(color: sem.danger),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppBadge(
            text: valid ? 'OK' : 'Invalid',
            tone: valid ? AppBadgeTone.success : AppBadgeTone.danger,
          ),
        ],
      ),
    );
  }
}

/// Determinate progress bar shown while rows are being inserted.
class _ImportProgress extends StatelessWidget {
  const _ImportProgress({required this.processed, required this.total});

  final int processed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = total == 0 ? null : processed / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(value: value),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Importing… $processed of $total',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Post-import results: a tinted headline + an expandable per-row error report.
class _ResultSummary extends StatelessWidget {
  const _ResultSummary({
    required this.imported,
    required this.failed,
    required this.failures,
  });

  final int imported;
  final int failed;
  final List<_RowFailure> failures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sem = AppSemanticColors.of(context);
    final hadFailures = failed > 0;
    final bg = hadFailures ? sem.warningContainer : sem.successContainer;
    final fg = hadFailures ? sem.warning : sem.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hadFailures ? Icons.warning_amber_outlined : Icons.check_circle_outline,
                color: fg,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Imported $imported · failed $failed',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (failures.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'View ${failures.length} failed row(s)',
                  style: theme.textTheme.bodyMedium,
                ),
                children: [
                  for (final f in failures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Row ${f.rowNumber}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: AppType.semibold,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              f.message,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
