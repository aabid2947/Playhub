/// One file attached to a chat message. Stored as a JSONB object in
/// messages.attachments[]; the storage object lives in the private
/// `chat_attachments` bucket under <academy_id>/<thread_id>/<uuid>.<ext>.
class ChatAttachment {
  const ChatAttachment({
    required this.path,
    required this.name,
    required this.mime,
    this.sizeBytes,
  });

  /// Accepts both legacy-string ("path/foo.jpg") and current-object shapes.
  factory ChatAttachment.fromAny(Object raw) {
    if (raw is String) {
      final lower = raw.toLowerCase();
      final dot = lower.lastIndexOf('.');
      final ext = dot == -1 ? '' : lower.substring(dot);
      return ChatAttachment(
        path: raw,
        name: raw.split('/').last,
        mime: _mimeFromExt(ext),
      );
    }
    final m = (raw as Map).cast<String, dynamic>();
    return ChatAttachment(
      path: m['path'] as String,
      name: (m['name'] as String?) ?? (m['path'] as String).split('/').last,
      mime: (m['mime'] as String?) ?? 'application/octet-stream',
      sizeBytes: (m['size'] as int?) ?? (m['size_bytes'] as int?),
    );
  }

  final String path;
  final String name;
  final String mime;
  final int? sizeBytes;

  bool get isImage => mime.startsWith('image/');
  bool get isVideo => mime.startsWith('video/');
  bool get isDocument => !isImage && !isVideo;

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'mime': mime,
        if (sizeBytes != null) 'size': sizeBytes,
      };
}

String _mimeFromExt(String ext) {
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    case '.heic':
      return 'image/heic';
    case '.gif':
      return 'image/gif';
    case '.mp4':
      return 'video/mp4';
    case '.mov':
      return 'video/quicktime';
    case '.webm':
      return 'video/webm';
    case '.m4v':
      return 'video/x-m4v';
    case '.pdf':
      return 'application/pdf';
    case '.doc':
      return 'application/msword';
    case '.docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case '.xls':
      return 'application/vnd.ms-excel';
    case '.xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case '.txt':
      return 'text/plain';
    case '.csv':
      return 'text/csv';
  }
  return 'application/octet-stream';
}
