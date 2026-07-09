// `_rows`/`_headers` are nullable until the user picks a file; the lint
// would prefer `late` non-nullable but that's wrong for this state machine.
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
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Required CSV header columns.
const _requiredCols = ['first_name', 'last_name', 'parent_name'];

/// All recognised CSV columns. Anything else is ignored.
const _allCols = [
  'first_name',
  'last_name',
  'parent_name',
  'parent_phone',
  'parent_email',
  'date_of_birth', // YYYY-MM-DD
  'gender',
  'sport',
  'skill_level',
  'city',
];

const _templateCsv =
    'first_name,last_name,parent_name,parent_phone,parent_email,date_of_birth,gender,sport,skill_level,city\n'
    'Aarav,Sharma,Priya Sharma,9876543210,priya@example.com,2015-03-12,male,Cricket,beginner,Mumbai\n'
    'Ananya,Iyer,Ravi Iyer,9876543211,,2014-09-05,female,Badminton,intermediate,Chennai\n';

/// A single row failure surfaced in the results report.
class _RowFailure {
  const _RowFailure(this.rowNumber, this.message);

  /// 1-based row number as it appears in the CSV (header excluded).
  final int rowNumber;
  final String message;
}

class StudentBulkImportPage extends ConsumerStatefulWidget {
  const StudentBulkImportPage({super.key});

  @override
  ConsumerState<StudentBulkImportPage> createState() =>
      _StudentBulkImportPageState();
}

class _StudentBulkImportPageState extends ConsumerState<StudentBulkImportPage> {
  List<Map<String, String>>? _rows;
  List<String>? _headers;
  String? _error;
  String? _filename;
  // Required target center applied to EVERY imported student — students.center_id
  // is NOT NULL at the DB (20260710000000), so a center-less insert now fails.
  String? _centerId;
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
        _headers = headers;
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
        _error = 'Pick a center to import students into.';
      });
      return;
    }

    final client = ref.read(supabaseClientProvider);

    // Build a name → sport_id lookup off the academy's enabled sports so
    // the CSV's free-text 'sport' column maps to the catalog. Unknown
    // values fall through unmapped.
    final enabledSports =
        await ref.read(academyCenterSportsProvider.future);
    final sportLookup = <String, String>{
      for (final s in enabledSports) ...{
        s.displayName.toLowerCase(): s.sport.id,
        s.sport.code.toLowerCase(): s.sport.id,
        s.sport.name.toLowerCase(): s.sport.id,
      }
    };

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
      final sportText = r['sport']?.trim().toLowerCase();
      final sportId =
          sportText != null && sportText.isNotEmpty ? sportLookup[sportText] : null;
      try {
        await client.from('students').insert({
          'academy_id': academyId,
          'center_id': centerId,
          'first_name': r['first_name'],
          'last_name': r['last_name'],
          'parent_name': r['parent_name'],
          if (r['parent_phone'] != null) 'parent_phone': r['parent_phone'],
          if (r['parent_email'] != null) 'parent_email': r['parent_email'],
          if (r['date_of_birth'] != null) 'date_of_birth': r['date_of_birth'],
          if (r['gender'] != null) 'gender': r['gender'],
          if (sportId != null) 'sport_id': sportId,
          if (r['skill_level'] != null) 'skill_level': r['skill_level'],
          if (r['city'] != null) 'city': r['city'],
        });
        ok++;
      } on Object catch (e) {
        fail++;
        failures.add(_RowFailure(rowNumber, friendlyError(e)));
      }
      if (mounted) setState(() => _processed = i + 1);
    }
    ref.invalidate(studentsProvider);
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
        title: const Text('Import students'),
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
                  tone: AppBadgeTone.neutral,
                ),
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
                      headers: _headers!,
                      rows: rows,
                      isValid: _isValid,
                      missingRequired: _missingRequired,
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text('Import $validCount valid rows'),
                      onPressed: (_busy || validCount == 0 || _centerId == null)
                          ? null
                          : _import,
                    ),
                  ),
                  if (_centerId == null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Pick a center above to enable importing.',
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

/// Required target-center dropdown applied to the whole import. Its own
/// ConsumerWidget so it can read `centersProvider`; when the academy has no
/// center it blocks with guidance (students.center_id is NOT NULL at the DB).
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
                message: 'Create a center first — imported students must '
                    'belong to a center.',
              );
            }
            return AppDropdownField<String>(
              label: 'Import all students into center *',
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

/// A wrap of column-name pills.
class _ColumnChips extends StatelessWidget {
  const _ColumnChips({required this.columns, required this.tone});

  final List<String> columns;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final c in columns) AppBadge(text: c, tone: tone),
      ],
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
    required this.headers,
    required this.rows,
    required this.isValid,
    required this.missingRequired,
  });

  final List<String> headers;
  final List<Map<String, String>> rows;
  final bool Function(Map<String, String>) isValid;
  final List<String> Function(Map<String, String>) missingRequired;

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
  });

  final int rowNumber;
  final Map<String, String> row;
  final bool valid;
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);

    final name = [row['first_name'], row['last_name']]
        .where((v) => v != null && v.isNotEmpty)
        .join(' ');
    final secondary = [
      if ((row['parent_name'] ?? '').isNotEmpty) row['parent_name'],
      if ((row['sport'] ?? '').isNotEmpty) row['sport'],
      if ((row['city'] ?? '').isNotEmpty) row['city'],
    ].whereType<String>().join(' · ');

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
