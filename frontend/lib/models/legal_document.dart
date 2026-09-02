import 'package:cloud_firestore/cloud_firestore.dart';

/// a legal document (privacy policy, terms of service, employee data notice)
/// stored in Firestore so the owner can edit the wording themselves without a
/// code deploy. [content] uses a small plain-text markup this app's renderer
/// understands: a line starting with "# " is the document title, "## " is a
/// section heading, "- " is a bullet item, and a blank line starts a new
/// paragraph — see [LegalDocumentIds] for the fixed set of documents this app
/// actually surfaces.
class LegalDocument {
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

/// fixed doc IDs for the three legal documents this app surfaces — matches
/// the seed script (backend/scripts/seed_legal_documents.py) and every
/// signup/settings screen that links to one of these.
class LegalDocumentIds {
  static const privacyPolicy = 'privacy_policy';
  static const termsOfService = 'terms_of_service';
  static const employeeDataNotice = 'employee_data_notice';
}
