import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/common_service.dart';

/// manages the owner's reusable "common services" catalog in firestore
class ServiceCatalogService {
  ServiceCatalogService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('service_catalog');

  /// stream the full catalog, sorted by name
  static Stream<List<CommonService>> watchAllServices() {
    return _collection.snapshots().map((snapshot) {
      final services = snapshot.docs
          .map((doc) => CommonService.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      services.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return services;
    });
  }

  /// search catalog entries by name or description
  static List<CommonService> searchServices({
    required List<CommonService> services,
    required String query,
    int limit = 8,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <CommonService>[];
    }

    final matches = services.where((service) {
      final searchable = <String>[service.name, service.description]
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty);
      for (final value in searchable) {
        if (value.contains(normalizedQuery)) return true;
      }
      return false;
    }).toList();

    if (matches.length > limit) {
      return matches.sublist(0, limit);
    }
    return matches;
  }

  /// create (id null/empty) or update (id provided) a catalog entry
  static Future<void> saveService({
    String? id,
    required String name,
    required String description,
    String? unit,
    double? unitPrice,
    double? flatPrice,
  }) async {
    final normalizedId = id?.trim();
    final doc = (normalizedId == null || normalizedId.isEmpty) ? _collection.doc() : _collection.doc(normalizedId);

    final service = CommonService(
      id: doc.id,
      name: name.trim(),
      description: description.trim(),
      unit: unit?.trim(),
      unitPrice: unitPrice,
      flatPrice: flatPrice,
      createdAt: DateTime.now(),
    );

    await doc.set(service.toMap(), SetOptions(merge: true));
  }

  static Future<void> deleteService(String id) async {
    await _collection.doc(id.trim()).delete();
  }
}
