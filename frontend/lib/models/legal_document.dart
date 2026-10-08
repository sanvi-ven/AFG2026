import 'package:cloud_firestore/cloud_firestore.dart';

/// a legal document (privacy policy, terms of service, employee data notice)
/// stored in Firestore so the owner can edit the wording themselves without a
/// code deploy. [content] uses a small plain-text markup this app's renderer
/// understands: a line starting with "# " is the document title, "## " is a
/// section heading, "- " is a bullet item, and a blank line starts a new
/// paragraph — see [LegalDocumentIds] for the fixed set of documents this app
/// actually surfaces.
class LegalDocument {
  /// splits [content] into the markup's blocks, also breaking a block apart
  /// wherever a heading line or a switch between bullet and plain lines sits
  /// directly under another line with no blank line between them (e.g. the
  /// Fall Cleanup Policy's "## What's Included" followed straight by text),
  /// which would otherwise render the whole run as one heading or paragraph.
  static List<String> splitBlocks(String content) {
    final blocks = <String>[];
    var current = <String>[];
    String? currentKind;
    void flush() {
      if (current.isNotEmpty) blocks.add(current.join('\n'));
      current = <String>[];
      currentKind = null;
    }

    for (final line in content.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) {
        flush();
        continue;
      }
      final kind = trimmed.startsWith('#')
          ? 'heading'
          : trimmed.startsWith('- ')
              ? 'bullet'
              : 'text';
      if (kind == 'heading' || kind != currentKind) flush();
      current.add(line);
      currentKind = kind;
      if (kind == 'heading') flush();
    }
    flush();
    return blocks;
  }

  const LegalDocument({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final DateTime updatedAt;

  factory LegalDocument.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return LegalDocument(
      id: (map['id'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      content: (map['content'] as String? ?? ''),
      updatedAt: readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'updatedAt': updatedAt,
    };
  }
}

/// fixed doc IDs for the legal documents this app surfaces — matches
/// the seed script (backend/scripts/seed_legal_documents.py) and every
/// signup/settings screen that links to one of these.
class LegalDocumentIds {
  static const privacyPolicy = 'privacy_policy';
  static const termsOfService = 'terms_of_service';
  static const employeeDataNotice = 'employee_data_notice';

  /// the owner-editable master template an issued EmploymentContract's
  /// content is copied (frozen) from — not shown pre-auth like the other
  /// three, only via the owner's Manage Legal Documents admin page.
  static const employmentContractTemplate = 'employment_contract_template';

  /// the owner-editable fall cleanup policy (what's included in each
  /// package, leaf disposal, scheduling/weather, payment/cancellation, etc).
  /// Appended to every Fall Cleanup template estimate's PDF and linked from
  /// the estimate in-app; its current content is used, not a frozen copy.
  static const fallCleanupPolicy = 'fall_cleanup_policy';
}
