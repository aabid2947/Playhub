/// One AI-generated progress summary for a student, returned by the
/// `ai-insights` edge function. Hand-written `fromMap` per project convention.
class StudentInsight {
  const StudentInsight({
    required this.summary,
    required this.attendance,
    required this.performance,
    required this.focus,
  });

  factory StudentInsight.fromMap(Map<String, dynamic> m) => StudentInsight(
        summary: (m['summary'] as String?)?.trim() ?? '',
        attendance: (m['attendance'] as String?)?.trim() ?? '',
        performance: (m['performance'] as String?)?.trim() ?? '',
        focus: ((m['focus'] as List?) ?? const <dynamic>[])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false),
      );

  /// 2-sentence overall picture.
  final String summary;

  /// Attendance-consistency note.
  final String attendance;

  /// Performance-trend note.
  final String performance;

  /// 2–3 concrete things to work on.
  final List<String> focus;
}
