import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/equipment_kit.dart';

/// manages saved equipment kits (preset lists like "Mowing setup"). Staff-shared
/// CRUD — any owner or employee can create/edit/delete any kit, matching this
/// app's equipment/teams "full parity" design (see equipment_kit.dart).
class EquipmentKitService {
  EquipmentKitService._();

  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('equipment_kits');

  static Stream<List<EquipmentKit>> watchAllKits() {
    return _collection.snapshots().map((snapshot) {
      final kits = snapshot.docs
          .map((doc) => EquipmentKit.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      kits.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return kits;
    });
  }

  static Future<EquipmentKit?> fetchOnce(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;
    return EquipmentKit.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// create (id null/empty) or update (id provided) a kit.
  static Future<void> saveKit({
    String? id,
    required String name,
    String description = '',
    required List<EquipmentKitItem> items,
    required String createdByName,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('A kit needs a name.');
    }
    if (items.isEmpty) {
      throw Exception('A kit needs at least one item.');
    }

    final normalizedId = id?.trim();
    final isNew = normalizedId == null || normalizedId.isEmpty;
    final doc = isNew ? _collection.doc() : _collection.doc(normalizedId);
    final now = DateTime.now();

    // preserve the original creator's attribution across edits by other
    // staff — createdByName is set once, at creation, never overwritten by
    // whoever edits the kit later.
    final existingData = isNew ? null : (await doc.get()).data();
    final existingCreatedAt = existingData?['createdAt'];

    final kit = EquipmentKit(
      id: doc.id,
      name: trimmedName,
      description: description.trim(),
      items: items,
      createdByName: isNew
          ? createdByName
          : ((existingData?['createdByName'] as String?) ?? createdByName),
      createdAt: existingCreatedAt is Timestamp
          ? existingCreatedAt.toDate()
          : now,
      updatedAt: now,
    );

    await doc.set(kit.toMap(), SetOptions(merge: true));
  }

  static Future<void> deleteKit(String id) async {
    await _collection.doc(id.trim()).delete();
  }
}
