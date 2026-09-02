import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/legal_document_service.dart';
import '../../../models/legal_document.dart';
import '../../../shared/widgets/app_logo.dart';

/// view-only page for one legal document (privacy policy, terms of service,
/// employee data notice). Reachable both pre-auth (from signup/request-form
/// links, pushed without a role/authToken argument) and from inside the app
/// (from settings, with the normal role/authToken args) — this page needs no
/// role itself since the content is public.
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            AppLogo(size: 22),
            SizedBox(width: 10),
            Text('Anchor'),
          ],
        ),
      ),
      body: StreamBuilder<LegalDocument?>(
        stream: LegalDocumentService.watchDocument(documentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final document = snapshot.data;
          if (document == null) {
            return const Center(child: Text('This document is not available yet.'));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last updated ${DateFormat('MMMM d, yyyy').format(document.updatedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    LegalDocumentBody(content: document.content),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// splits [text] on "**bold**" pairs into plain/bold [TextSpan]s. The only
/// inline markup [LegalDocumentBody] supports — block-level structure
/// (headings/bullets/paragraphs) is handled by the caller.
List<InlineSpan> _parseInlineBold(String text, TextStyle? baseStyle) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'\*\*(.+?)\*\*');
  var lastEnd = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: baseStyle));
    }
    spans.add(TextSpan(
      text: match.group(1),
      style: baseStyle?.copyWith(fontWeight: FontWeight.w700),
    ));
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
  }
  return spans;
}

/// renders [LegalDocument.content]'s small plain-text markup: "# " is the
/// title, "## " is a section heading, "- " is a bullet item, "**text**" is
/// bold, and a blank line starts a new paragraph. Deliberately not full
/// markdown — this app has no markdown package dependency, and
/// legal-document text doesn't need more than this.
class LegalDocumentBody extends StatelessWidget {
  const LegalDocumentBody({required this.content, super.key});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = content.split('\n\n');
    final children = <Widget>[];

    for (final block in blocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('# ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(trimmed.substring(2).trim(),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ));
        continue;
      }
      if (trimmed.startsWith('## ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(trimmed.substring(3).trim(),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ));
        continue;
      }

      final lines = trimmed.split('\n');
      if (lines.every((line) => line.trimLeft().startsWith('- '))) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            children: _parseInlineBold(
                                line.trimLeft().substring(2).trim(), theme.textTheme.bodyMedium),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ));
        continue;
      }

      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: RichText(
          text: TextSpan(children: _parseInlineBold(trimmed, theme.textTheme.bodyMedium)),
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
