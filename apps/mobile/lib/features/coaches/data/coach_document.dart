class CoachDocument {
  const CoachDocument({
    required this.id,
    required this.academyId,
    required this.coachId,
    required this.type,
    required this.filePath,
    required this.uploadedAt,
    this.originalFilename,
    this.mimeType,
    this.sizeBytes,
    this.uploadedBy,
  });

  factory CoachDocument.fromMap(Map<String, dynamic> m) => CoachDocument(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        coachId: m['coach_id'] as String,
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
  final String coachId;
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

const kCoachDocumentTypes = [
  ('id_proof', 'ID proof'),
  ('qualification', 'Qualification'),
  ('certification', 'Certification'),
  ('photo', 'Photo'),
  ('contract', 'Contract'),
  ('other', 'Other'),
];

String labelForCoachDocType(String type) {
  for (final (k, label) in kCoachDocumentTypes) {
    if (k == type) return label;
  }
  return type;
}
