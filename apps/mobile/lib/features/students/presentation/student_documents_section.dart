import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/students/data/student_document.dart';
import 'package:playhub/features/students/data/student_document_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Short, human descriptions for each student document type, keyed by the
/// code in [kStudentDocumentTypes]. Shown under each option in the type
/// picker so the choice is unambiguous.
const _kStudentDocTypeHints = <String, String>{
  'id_proof': 'Aadhaar, passport or school ID',
  'medical_certificate': 'Fitness or medical clearance',
  'birth_certificate': 'Proof of date of birth',
  'photo': 'Passport-size or profile photo',
  'other': 'Anything that does not fit above',
};

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
        AppSectionHeader(
          title: 'Documents',
          trailing: FilledButton.tonalIcon(
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Upload'),
            onPressed: () => _pickTypeAndUpload(context, ref),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        docsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: AppLoading(),
          ),
          error: (e, _) => AppErrorView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(studentDocumentsProvider(studentId)),
          ),
          data: (docs) {
            if (docs.isEmpty) {
              return const AppCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No documents uploaded yet.'),
                      SizedBox(height: AppSpacing.xs),
                      _MutedHint(
                        'Use Upload to attach an ID proof, medical '
                        'certificate or photo.',
                      ),
                    ],
                  ),
                ),
              );
            }
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < docs.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _DocumentTile(
                      doc: docs[i],
                      onOpen: () => _openSigned(context, ref, docs[i]),
                      onDelete: () async {
                        final ok = await _confirmDelete(context, docs[i]);
                        if (ok) {
                          await deleteStudentDocument(ref, doc: docs[i]);
                        }
                      },
                    ),
                  ],
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
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  'What type of document?',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              for (final (k, label) in kStudentDocumentTypes)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(label),
                  subtitle: _kStudentDocTypeHints[k] != null
                      ? Text(_kStudentDocTypeHints[k]!)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(k),
                ),
            ],
          ),
        );
      },
    );
    if (type == null) return;
    try {
      await uploadStudentDocument(ref, studentId: studentId, type: type);
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _openSigned(
    BuildContext context,
    WidgetRef ref,
    StudentDocument d,
  ) async {
    try {
      final url = await signedUrlFor(ref, d);
      final uri = Uri.parse(url);
      await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication,
      );
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<bool> _confirmDelete(BuildContext context, StudentDocument d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${d.displayName}" will be removed. This cannot be '
            'undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.of(ctx).danger,
            ),
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
    final uploaded = DateFormat('dd MMM yyyy').format(doc.uploadedAt.toLocal());
    return AppListTile(
      wrapLeading: false,
      leading: Icon(_icon),
      isThreeLine: true,
      title: Text(
        doc.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBadge(text: labelForDocType(doc.type)),
            const SizedBox(height: AppSpacing.xs),
            _MutedHint('${doc.prettySize} • $uploaded'),
          ],
        ),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Document actions',
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

/// Small muted caption line used for metadata and hints in this section.
class _MutedHint extends StatelessWidget {
  const _MutedHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
