import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PickedDocument {
  const PickedDocument({
    required this.path,
    required this.originalFilename,
    required this.mimeType,
    required this.sizeBytes,
  });
  final String path;
  final String originalFilename;
  final String mimeType;
  final int sizeBytes;
}

/// Thin wrapper around `supabase.storage`. Knows three buckets:
///   avatars            (public)
///   student_documents  (private, signed URLs)
///   coach_documents    (private, signed URLs)
class StorageService {
  StorageService(this._client);

  final SupabaseClient _client;
  static const _avatarBucket = 'avatars';
  static final _picker = ImagePicker();

  // ---------------- Avatars ----------------

  Future<String?> pickAndUploadAvatar({
    required String academyId,
    required String entity, // 'students' | 'coaches' | 'academy'
  }) async {
    // `source` is non-default-required by image_picker but the lint
    // (avoid_redundant_argument_values) misreports it.
    // ignore: avoid_redundant_argument_values
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final ext = _extensionOf(picked.name);
    final path = '$academyId/$entity/${const Uuid().v4()}$ext';

    await _client.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentTypeOf(ext)),
        );

    return _client.storage.from(_avatarBucket).getPublicUrl(path);
  }

  Future<void> deleteByPublicUrl(String publicUrl) async {
    final path = _pathFromPublicUrl(publicUrl);
    if (path == null) return;
    try {
      await _client.storage.from(_avatarBucket).remove([path]);
    } on Object {
      // best effort
    }
  }

  // ---------------- Document buckets (shared) ----------------

  Future<PickedDocument?> _pickAndUploadDocument({
    required String bucket,
    required String folder, // e.g. "<academyId>/students/<id>"
  }) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
      type: FileType.custom,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError(
          'Picked file had no bytes (web requires withData: true)');
    }

    final ext = _extensionOf(file.name);
    final path = '$folder/${const Uuid().v4()}$ext';

    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentTypeOf(ext)),
        );

    return PickedDocument(
      path: path,
      originalFilename: file.name,
      mimeType: _contentTypeOf(ext),
      sizeBytes: bytes.length,
    );
  }

  Future<String> _signedUrl(String bucket, String path,
      {int expiresInSeconds = 300}) {
    return _client.storage
        .from(bucket)
        .createSignedUrl(path, expiresInSeconds);
  }

  Future<void> _deleteFromBucket(String bucket, String path) async {
    try {
      await _client.storage.from(bucket).remove([path]);
    } on Object {
      // best effort
    }
  }

  // ---------------- Student documents ----------------

  Future<PickedDocument?> pickAndUploadStudentDocument({
    required String academyId,
    required String studentId,
  }) =>
      _pickAndUploadDocument(
        bucket: 'student_documents',
        folder: '$academyId/students/$studentId',
      );

  Future<String> signedStudentDocumentUrl(String path,
          {int expiresInSeconds = 300}) =>
      _signedUrl('student_documents', path,
          expiresInSeconds: expiresInSeconds);

  Future<void> deleteStudentDocument(String path) =>
      _deleteFromBucket('student_documents', path);

  // ---------------- Coach documents ----------------

  Future<PickedDocument?> pickAndUploadCoachDocument({
    required String academyId,
    required String coachId,
  }) =>
      _pickAndUploadDocument(
        bucket: 'coach_documents',
        folder: '$academyId/coaches/$coachId',
      );

  Future<String> signedCoachDocumentUrl(String path,
          {int expiresInSeconds = 300}) =>
      _signedUrl('coach_documents', path,
          expiresInSeconds: expiresInSeconds);

  Future<void> deleteCoachDocument(String path) =>
      _deleteFromBucket('coach_documents', path);

  // ---------------- Performance media ----------------
  // Photo or video evidence attached to a `performance_assessments` row.
  // Path layout: <academyId>/assessments/<assessmentId>/<uuid>.<ext>

  Future<PickedDocument?> pickAndUploadPerformancePhoto({
    required String academyId,
    required String assessmentId,
  }) async {
    // image_picker requires `source`; lint flags it as redundant default.
    // ignore: avoid_redundant_argument_values
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final ext = _extensionOf(picked.name);
    final path = '$academyId/assessments/$assessmentId/${const Uuid().v4()}$ext';
    await _client.storage.from('performance_media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentTypeOf(ext)),
        );
    return PickedDocument(
      path: path,
      originalFilename: picked.name,
      mimeType: _contentTypeOf(ext),
      sizeBytes: bytes.length,
    );
  }

  Future<PickedDocument?> pickAndUploadPerformanceVideo({
    required String academyId,
    required String assessmentId,
  }) async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final name = picked.name;
    final ext = _extensionOf(name);
    final path = '$academyId/assessments/$assessmentId/${const Uuid().v4()}$ext';
    final mime = _videoContentTypeOf(ext);
    await _client.storage.from('performance_media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime),
        );
    return PickedDocument(
      path: path,
      originalFilename: name,
      mimeType: mime,
      sizeBytes: bytes.length,
    );
  }

  Future<String> signedPerformanceMediaUrl(String path,
          {int expiresInSeconds = 300}) =>
      _signedUrl('performance_media', path,
          expiresInSeconds: expiresInSeconds);

  Future<void> deletePerformanceMedia(String path) =>
      _deleteFromBucket('performance_media', path);

  // ---------------- Compatibility shim ----------------

  /// Old name kept for the existing student-documents callers.
  Future<String> signedDocumentUrl(String path,
          {int expiresInSeconds = 300}) =>
      signedStudentDocumentUrl(path, expiresInSeconds: expiresInSeconds);

  // ---------------- Helpers ----------------

  String? _pathFromPublicUrl(String url) {
    const marker = '/storage/v1/object/public/$_avatarBucket/';
    final i = url.indexOf(marker);
    if (i == -1) return null;
    return url.substring(i + marker.length);
  }

  String _extensionOf(String filename) {
    final i = filename.lastIndexOf('.');
    if (i == -1) return '.jpg';
    return filename.substring(i).toLowerCase();
  }

  String _contentTypeOf(String ext) {
    return switch (ext) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.heic' || '.heif' => 'image/heic',
      _ => 'image/jpeg',
    };
  }

  String _videoContentTypeOf(String ext) {
    return switch (ext) {
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      '.m4v' => 'video/x-m4v',
      _ => 'video/mp4',
    };
  }
}
