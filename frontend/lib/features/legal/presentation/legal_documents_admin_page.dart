import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/legal_document_service.dart';
import '../../../models/legal_document.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// owner-only screen listing the app's three legal documents, each editable
/// in place — lets the owner update wording (contact info, policy changes)
/// without a code deploy.
class LegalDocumentsAdminPage extends StatelessWidget {
  const LegalDocumentsAdminPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  static const _documents = [
    (id: LegalDocumentIds.privacyPolicy, title: 'Privacy Policy'),
    (id: LegalDocumentIds.termsOfService, title: 'Terms of Service'),
    (id: LegalDocumentIds.employeeDataNotice, title: 'Employee Data Privacy Notice'),
  ];

  @override
  Widget build(BuildContext context) {
    if (role != 'owner') {
      return const SizedBox.shrink();
    }

    return AppScaffold(
      title: 'Legal Documents',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.legalDocumentsAdmin,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'These are the documents shown to clients and employees at signup and in their settings. '
            'Editing here updates them everywhere immediately.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final doc in _documents)
            StreamBuilder<LegalDocument?>(
              stream: LegalDocumentService.watchDocument(doc.id),
              builder: (context, snapshot) {
                final document = snapshot.data;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(doc.title),
                    subtitle: Text(document == null
                        ? 'Not set up yet'
                        : 'Last updated ${DateFormat('MMM d, yyyy').format(document.updatedAt)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRouter.legalDocumentEdit,
                      arguments: {
                        'role': role,
                        'authToken': authToken,
                        'documentId': doc.id,
                        'documentTitle': doc.title,
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// full-page editor for one legal document's content — a plain multiline text
/// field, since these documents run long and a dialog would be cramped.
class LegalDocumentEditPage extends StatefulWidget {
  const LegalDocumentEditPage({
    required this.role,
    this.authToken,
    required this.documentId,
    required this.documentTitle,
    super.key,
  });

  final String role;
  final String? authToken;
  final String documentId;
  final String documentTitle;

  @override
  State<LegalDocumentEditPage> createState() => _LegalDocumentEditPageState();
}

class _LegalDocumentEditPageState extends State<LegalDocumentEditPage> {
  final _contentController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final document = await LegalDocumentService.fetchDocument(widget.documentId);
    if (!mounted) return;
    setState(() {
      _contentController.text = document?.content ?? '';
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await LegalDocumentService.saveDocument(
        id: widget.documentId,
        title: widget.documentTitle,
        content: _contentController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: ${error.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.documentTitle}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A line starting with "# " is the document title, "## " starts a section '
                    'heading, "- " starts a bullet item, and a blank line starts a new paragraph.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: _contentController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
