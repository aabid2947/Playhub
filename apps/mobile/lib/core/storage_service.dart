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

/// Thin wrapper around `supabase.storage` for the `avatars` bucket.
/// Path layout: `<academyId>/<entity>/<uuid>.<ext>`.
class StorageService {
  StorageService(this._client);

  final SupabaseClient _client;
  static const _bucket = 'avatars';
  static final _picker = ImagePicker();

  /// Lets the user pick an image, uploads it, and returns the public URL.
  /// Returns null if the user cancels.
  Future<String?> pickAndUploadAvatar({
    required String academyId,
    required String entity, // 'students' | 'coaches' | 'academy'
  }) async {
    // `source` is non-default-required by image_picker but the lint
    // (avoid_redundant_argument_values) misreports it. Hardcoded to gallery
    // — camera support comes with the biometric/attendance flow later.
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

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentTypeOf(ext)),
        );

    return _client.storage.from(_bucket).getPublicUrl(path);
  }

  /// Lets the user pick any file (PDF, image, doc) and uploads it to the
  /// private `student_documents` bucket. Returns metadata the caller can
  /// persist to the `student_documents` table. Returns null if cancelled.
  Future<PickedDocument?> pickAndUploadStudentDocument({
    required String academyId,
    required String studentId,
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
      throw StateError('Picked file had no bytes (web requires withData: true)');
    }

    final ext = _extensionOf(file.name);
    final path =
        '$academyId/students/$studentId/${const Uuid().v4()}$ext';

    await _client.storage.from('student_documents').uploadBinary(
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

  /// Generates a short-lived signed URL for a private student-document path.
  Future<String> signedDocumentUrl(String path,
      {int expiresInSeconds = 300}) {
    return _client.storage
        .from('student_documents')
        .createSignedUrl(path, expiresInSeconds);
  }

  /// Removes a file from the private documents bucket. Used when an admin
  /// deletes the row.
  Future<void> deleteStudentDocument(String path) async {
    try {
      await _client.storage.from('student_documents').remove([path]);
    } on Object {
      // Best effort — table row removal still happens.
    }
  }

  /// Best-effort delete of a previously uploaded avatar URL.
  /// Failures are swallowed — orphaned files are cleaned up by a later
  /// scheduled job.
  Future<void> deleteByPublicUrl(String publicUrl) async {
    final path = _pathFromPublicUrl(publicUrl);
    if (path == null) return;
    try {
      await _client.storage.from(_bucket).remove([path]);
    } on Object {
      // ignore
    }
  }

  String? _pathFromPublicUrl(String url) {
    const marker = '/storage/v1/object/public/$_bucket/';
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
}
