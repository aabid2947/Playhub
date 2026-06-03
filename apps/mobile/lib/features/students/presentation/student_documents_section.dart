import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/students/data/student_document.dart';
import 'package:playhub/features/students/data/student_document_providers.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:playhub/core/error_messages.dart';

/// Embedded section listing a student's documents and offering upload + open
/// + delete. Caller should only render this once the student row exists in
/// the database (i.e. in edit mode, not the create form).
class StudentDocumentsSection extends ConsumerWidget {
  const StudentDocumentsSection({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(studentDocumentsProvider(studentId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Documents',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Upload'),
              onPressed: () => _pickTypeAndUpload(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 8),
        docsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (e, _) => Text(friendlyError(e)),
          data: (docs) {
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No documents uploaded yet.'),
              );
            }
            return Card(
              child: Column(
                children: [
                  for (final d in docs)
                    _DocumentTile(
                      doc: d,
                      onOpen: () => _openSigned(context, ref, d),
                      onDelete: () async {
                        final ok = await _confirmDelete(context);
                        if (ok) {
                          await deleteStudentDocument(ref, doc: d);
                        }
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickTypeAndUpload(BuildContext context, WidgetRef ref) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('What type of document?'),
              dense: true,
            ),
            const Divider(height: 1),
            for (final (k, label) in kStudentDocumentTypes)
              ListTile(
                title: Text(label),
                onTap: () => Navigator.of(ctx).pop(k),
              ),
          ],
        ),
      ),
    );
    if (type == null) return;
    try {
      await uploadStudentDocument(ref, studentId: studentId, type: type);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _openSigned(
      BuildContext context, WidgetRef ref, StudentDocument d) async {
    try {
      final url = await signedUrlFor(ref, d);
      final uri = Uri.parse(url);
      await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.doc,
    required this.onOpen,
    required this.onDelete,
  });
  final StudentDocument doc;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  IconData get _icon {
    final mt = doc.mimeType ?? '';
    if (mt.startsWith('image/')) return Icons.image_outlined;
    if (mt == 'application/pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon),
      title: Text(doc.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${labelForDocType(doc.type)} • ${doc.prettySize}'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'open') onOpen();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'open', child: Text('Open')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onOpen,
    );
  }
}
