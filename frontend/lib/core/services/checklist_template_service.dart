import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/checklist_template.dart';

/// manages the owner's reusable job checklist templates in firestore
class ChecklistTemplateService {
  ChecklistTemplateService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('checklist_templates');

  /// stream all templates, sorted by name
  static Stream<List<ChecklistTemplate>> watchAllTemplates() {
    return _collection.snapshots().map((snapshot) {
      final templates = snapshot.docs
          .map((doc) => ChecklistTemplate.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      templates.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return templates;
    });
  }

  /// search templates by name
  static List<ChecklistTemplate> searchTemplates({
    required List<ChecklistTemplate> templates,
    required String query,
    int limit = 8,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <ChecklistTemplate>[];
    }

    final matches =
        templates.where((template) => template.name.trim().toLowerCase().contains(normalizedQuery)).toList();

    if (matches.length > limit) {
      return matches.sublist(0, limit);
    }
    return matches;
  }

  /// create (id null/empty) or update (id provided) a template
  static Future<void> saveTemplate({
    String? id,
    required String name,
    required List<String> items,
  }) async {
    final normalizedId = id?.trim();
    final doc = (normalizedId == null || normalizedId.isEmpty) ? _collection.doc() : _collection.doc(normalizedId);

    final template = ChecklistTemplate(
      id: doc.id,
      name: name.trim(),
      items: items,
      createdAt: DateTime.now(),
    );

    await doc.set(template.toMap(), SetOptions(merge: true));
  }

  static Future<void> deleteTemplate(String id) async {
    await _collection.doc(id.trim()).delete();
  }
}
