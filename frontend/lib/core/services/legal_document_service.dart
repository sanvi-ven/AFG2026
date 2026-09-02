import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/legal_document.dart';

/// manages legal documents (privacy policy, terms of service, employee data
/// notice). Publicly readable (needed pre-auth on the signup/quote-request
/// screens), owner-only to write — see firestore.rules.
class LegalDocumentService {
  LegalDocumentService._();

  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('legal_documents');

  static Stream<LegalDocument?> watchDocument(String id) {
    return _collection.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return LegalDocument.fromMap({...?doc.data(), 'id': doc.id});
    });
  }

  static Future<LegalDocument?> fetchDocument(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;
    return LegalDocument.fromMap({...?doc.data(), 'id': doc.id});
  }

  static Future<void> saveDocument({
    required String id,
    required String title,
    required String content,
  }) async {
    await _collection.doc(id).set(
      {
        'id': id,
        'title': title,
        'content': content,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }
}
