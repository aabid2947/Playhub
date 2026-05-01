class StudentDocument {
  const StudentDocument({
    required this.id,
    required this.academyId,
    required this.studentId,
    required this.type,
    required this.filePath,
    required this.uploadedAt,
    this.originalFilename,
    this.mimeType,
    this.sizeBytes,
    this.uploadedBy,
  });

  factory StudentDocument.fromMap(Map<String, dynamic> m) => StudentDocument(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        studentId: m['student_id'] as String,
        type: m['type'] as String,
        filePath: m['file_path'] as String,
        originalFilename: m['original_filename'] as String?,
        mimeType: m['mime_type'] as String?,
        sizeBytes: m['size_bytes'] as int?,
        uploadedBy: m['uploaded_by'] as String?,
        uploadedAt: DateTime.parse(m['uploaded_at'] as String),
      );

  final String id;
  final String academyId;
  final String studentId;
  final String type;
  final String filePath;
  final String? originalFilename;
  final String? mimeType;
  final int? sizeBytes;
  final String? uploadedBy;
  final DateTime uploadedAt;

  String get displayName => originalFilename ?? filePath.split('/').last;

  String get prettySize {
    final n = sizeBytes ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

const kStudentDocumentTypes = [
  ('id_proof', 'ID proof'),
  ('medical_certificate', 'Medical certificate'),
  ('birth_certificate', 'Birth certificate'),
  ('photo', 'Photo'),
  ('other', 'Other'),
];

String labelForDocType(String type) {
  for (final (k, label) in kStudentDocumentTypes) {
    if (k == type) return label;
  }
  return type;
}
