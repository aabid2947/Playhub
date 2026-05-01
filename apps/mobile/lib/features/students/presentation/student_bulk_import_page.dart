// `_rows`/`_headers` are nullable until the user picks a file; the lint
// would prefer `late` non-nullable but that's wrong for this state machine.
// ignore_for_file: use_late_for_private_fields_and_variables

import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/students/data/student_providers.dart';

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
  bool _busy = false;
  int? _imported;
  int? _failed;

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

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null) return;
    setState(() {
      _busy = true;
      _imported = null;
      _failed = null;
      _error = null;
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

    final client = ref.read(supabaseClientProvider);
    var ok = 0;
    var fail = 0;
    for (final r in rows) {
      if (!_isValid(r)) {
        fail++;
        continue;
      }
      try {
        await client.from('students').insert({
          'academy_id': academyId,
          'first_name': r['first_name'],
          'last_name': r['last_name'],
          'parent_name': r['parent_name'],
          if (r['parent_phone'] != null) 'parent_phone': r['parent_phone'],
          if (r['parent_email'] != null) 'parent_email': r['parent_email'],
          if (r['date_of_birth'] != null) 'date_of_birth': r['date_of_birth'],
          if (r['gender'] != null) 'gender': r['gender'],
          if (r['sport'] != null) 'sport': r['sport'],
          if (r['skill_level'] != null) 'skill_level': r['skill_level'],
          if (r['city'] != null) 'city': r['city'],
        });
        ok++;
      } on Object {
        fail++;
      }
    }
    ref.invalidate(studentsProvider);
    setState(() {
      _busy = false;
      _imported = ok;
      _failed = fail;
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
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Required columns: ${_requiredCols.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Optional: ${_allCols.where((c) => !_requiredCols.contains(c)).join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Pick CSV'),
                onPressed: _pick,
              ),
              const SizedBox(width: 12),
              if (_filename != null) Expanded(child: Text(_filename!)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_rows != null) ...[
            const SizedBox(height: 16),
            _PreviewTable(headers: _headers!, rows: _rows!, isValid: _isValid),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _import,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Import ${_rows!.where(_isValid).length} rows'),
            ),
          ],
          if (_imported != null) ...[
            const SizedBox(height: 16),
            Card(
              color: (_failed ?? 0) > 0
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.green.withValues(alpha: 0.15),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Imported $_imported · failed ${_failed ?? 0}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewTable extends StatelessWidget {
  const _PreviewTable({
    required this.headers,
    required this.rows,
    required this.isValid,
  });

  final List<String> headers;
  final List<Map<String, String>> rows;
  final bool Function(Map<String, String>) isValid;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final h in headers) DataColumn(label: Text(h)),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                color: WidgetStateProperty.resolveWith((states) {
                  return isValid(r) ? null : Colors.red.withValues(alpha: 0.10);
                }),
                cells: [
                  for (final h in headers) DataCell(Text(r[h] ?? '')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
