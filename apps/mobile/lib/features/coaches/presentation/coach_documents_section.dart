import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/coaches/data/coach_document.dart';
import 'package:playhub/features/coaches/data/coach_document_providers.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

class CoachDocumentsSection extends ConsumerWidget {
  const CoachDocumentsSection({required this.coachId, super.key});

  final String coachId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(coachDocumentsProvider(coachId));

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
          error: (e, _) => Text('Error: $e'),
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
                          await deleteCoachDocument(ref, doc: d);
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
              dense: true,
              title: Text('What type of document?'),
            ),
            const Divider(height: 1),
            for (final (k, label) in kCoachDocumentTypes)
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
      await uploadCoachDocument(ref, coachId: coachId, type: type);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Future<void> _openSigned(
      BuildContext context, WidgetRef ref, CoachDocument d) async {
    try {
      final url = await coachDocumentSignedUrl(ref, d);
      await launcher.launchUrl(
        Uri.parse(url),
        mode: launcher.LaunchMode.externalApplication,
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
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
  final CoachDocument doc;
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
      subtitle: Text(
          '${labelForCoachDocType(doc.type)} • ${doc.prettySize}'),
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
