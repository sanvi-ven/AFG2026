import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/equipment.dart';

/// manages the equipment catalog — durable Equipment items (numbered units)
/// and consumable Supply items. Follows this codebase's static-service +
/// direct-Firestore convention (see RequestService). Catalog CRUD + photos
/// only in this phase; unit/reservation/service methods arrive in later phases.
class EquipmentService {
  EquipmentService._();

  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('equipment');

  /// mint a doc id up front so photos can be uploaded to a stable storage path
  /// (equipment_photos/{id}/) before the equipment document itself exists
  static String newEquipmentId() => _collection.doc().id;

  /// stream all catalog items, sorted by name (client-side). Archived items are
  /// hidden unless [includeArchived] is set.
  static Stream<List<EquipmentItem>> watchAll({bool includeArchived = false}) {
    return _collection.snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => EquipmentItem.fromMap({...doc.data(), 'id': doc.id}))
          .where((item) => includeArchived || !item.isArchived)
          .toList();
      items.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    });
  }

  /// stream a single catalog item, or null if the doc doesn't exist
  static Stream<EquipmentItem?> watchOne(String id) {
    return _collection.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return EquipmentItem.fromMap({...?doc.data(), 'id': doc.id});
    });
  }

  /// one-time fetch of a single catalog item, or null if it doesn't exist.
  /// Used where a fresh read is needed instead of trusting a possibly-stale
  /// value already in hand (e.g. re-checking unit statuses right before a
  /// reservation is booked).
  static Future<EquipmentItem?> fetchOnce(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;
    return EquipmentItem.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// create a catalog item. For Equipment, builds [quantity] units numbered
  /// 1..quantity all starting active; Supply has no units.
  static Future<void> createEquipment({
    required String id,
    required String name,
    required String type,
    List<String> photoUrls = const [],
    int quantity = 1,
    String unitOfMeasure = '',
    int? lowStockThreshold,
    int? defaultServiceIntervalDays,
  }) async {
    final now = DateTime.now();
    final units = type == EquipmentType.equipment
        ? <EquipmentUnit>[
            for (var i = 1; i <= quantity; i++)
              EquipmentUnit(
                unitNumber: i,
                status: EquipmentUnitStatus.active,
                serviceIntervalDays: defaultServiceIntervalDays,
              ),
          ]
        : const <EquipmentUnit>[];

    final item = EquipmentItem(
      id: id,
      type: type,
      name: name.trim(),
      photoUrls: photoUrls,
      quantity: quantity,
      unitOfMeasure: unitOfMeasure.trim(),
      lowStockThreshold: type == EquipmentType.supply ? lowStockThreshold : null,
      defaultServiceIntervalDays:
          type == EquipmentType.equipment ? defaultServiceIntervalDays : null,
      units: units,
      createdAt: now,
      updatedAt: now,
    );
    await _collection.doc(id).set(item.toMap());
  }

  /// merge-write catalog fields (plus updatedAt). Does NOT touch
  /// quantity/units — unit-count adjustment is a dedicated Phase 2 method.
  ///
  /// [name]/[photoUrls] are skipped when null (defensive, though the only
  /// caller — the equipment form — always supplies both). [unitOfMeasure],
  /// [lowStockThreshold], and [defaultServiceIntervalDays] are ALWAYS written
  /// (including null), since the form always knows the item's type and
  /// intends the type-inapplicable field to be cleared and the type-relevant
  /// field to reflect exactly what the user entered — otherwise a user
  /// blanking a threshold/interval field could never actually clear it.
  static Future<void> updateCatalogFields({
    required String id,
    String? name,
    List<String>? photoUrls,
    String? unitOfMeasure,
    int? lowStockThreshold,
    int? defaultServiceIntervalDays,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': DateTime.now(),
      'unitOfMeasure': unitOfMeasure?.trim() ?? '',
      'lowStockThreshold': lowStockThreshold,
      'defaultServiceIntervalDays': defaultServiceIntervalDays,
    };
    if (name != null) data['name'] = name.trim();
    if (photoUrls != null) data['photoUrls'] = photoUrls;
    await _collection.doc(id).set(data, SetOptions(merge: true));
  }

  /// soft delete — dependents (reservations/records) reference equipmentId
  static Future<void> archiveEquipment(String id) async {
    await _collection.doc(id).set(
      {'isArchived': true, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  static Future<void> restoreEquipment(String id) async {
    await _collection.doc(id).set(
      {'isArchived': false, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  static Future<void> setLowStockManualFlag({
    required String id,
    required bool flagged,
  }) async {
    await _collection.doc(id).set(
      {'lowStockManualFlag': flagged, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  // --- Phase 2: per-unit status + count adjustment ---------------------------

  /// flip a single unit's [status] (and, per the contract below, its
  /// [currentBrokenReportId]), then write the whole units list back via merge.
  ///
  /// currentBrokenReportId contract (keyed off [status] since the parameter
  /// can't distinguish "omitted" from "explicit null"):
  ///  - [EquipmentUnitStatus.broken]: pass the new report id; it is set.
  ///  - [EquipmentUnitStatus.active]: pass null; it is cleared to null.
  ///  - [EquipmentUnitStatus.inRepair]: the existing report id is preserved
  ///    (the parameter is ignored).
  static Future<void> setUnitStatus({
    required String equipmentId,
    required int unitNumber,
    required String status,
    String? currentBrokenReportId,
  }) async {
    final doc = await _collection.doc(equipmentId).get();
    if (!doc.exists) {
      throw Exception('Equipment $equipmentId no longer exists.');
    }
    final item = EquipmentItem.fromMap({...?doc.data(), 'id': doc.id});

    final index = item.units.indexWhere((u) => u.unitNumber == unitNumber);
    if (index < 0) {
      throw Exception('Unit #$unitNumber does not exist on this item.');
    }

    final existing = item.units[index];
    // inRepair keeps the current report id; broken/active use the parameter.
    final resolvedReportId = status == EquipmentUnitStatus.inRepair
        ? existing.currentBrokenReportId
        : currentBrokenReportId;

    final updatedUnits = List<EquipmentUnit>.from(item.units);
    updatedUnits[index] = EquipmentUnit(
      unitNumber: existing.unitNumber,
      status: status,
      currentBrokenReportId: resolvedReportId,
      lastServiceDate: existing.lastServiceDate,
      nextServiceDueDate: existing.nextServiceDueDate,
      serviceIntervalDays: existing.serviceIntervalDays,
      serviceDueSnoozedUntil: existing.serviceDueSnoozedUntil,
      serviceDueNotifiedAt: existing.serviceDueNotifiedAt,
    );

    await _collection.doc(equipmentId).set(
      {
        'units': updatedUnits.map((u) => u.toMap()).toList(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// grow or shrink an Equipment item's unit count. Growing appends new active
  /// units numbered `(currentMax + 1)..newQuantity`. Shrinking removes the
  /// HIGHEST-numbered units down to `newQuantity + 1`, but only if every
  /// removed unit is [EquipmentUnitStatus.active] (broken/inRepair units must
  /// be resolved first). Reservation-awareness is deferred to Phase 3.
  ///
  /// Throws if called on a Supply, if newQuantity < 1, or if a to-be-removed
  /// unit is not active.
  static Future<void> adjustEquipmentUnitCount({
    required String equipmentId,
    required int newQuantity,
  }) async {
    if (newQuantity < 1) {
      throw Exception('Equipment must have at least 1 unit.');
    }

    final doc = await _collection.doc(equipmentId).get();
    if (!doc.exists) {
      throw Exception('Equipment $equipmentId no longer exists.');
    }
    final item = EquipmentItem.fromMap({...?doc.data(), 'id': doc.id});

    if (item.type != EquipmentType.equipment) {
      throw Exception('Only Equipment items have adjustable units.');
    }

    final units = List<EquipmentUnit>.from(item.units);
    final currentCount = units.length;

    if (newQuantity > currentCount) {
      final currentMax = units.fold<int>(
          0, (max, u) => u.unitNumber > max ? u.unitNumber : max);
      for (var n = currentMax + 1; units.length < newQuantity; n++) {
        units.add(EquipmentUnit(
          unitNumber: n,
          status: EquipmentUnitStatus.active,
          serviceIntervalDays: item.defaultServiceIntervalDays,
        ));
      }
    } else if (newQuantity < currentCount) {
      // remove the highest-numbered units; guard that each is active.
      units.sort((a, b) => a.unitNumber.compareTo(b.unitNumber));
      final toRemove = units.sublist(newQuantity);
      for (final unit in toRemove) {
        if (unit.status != EquipmentUnitStatus.active) {
          throw Exception(
              'Cannot remove unit #${unit.unitNumber} — it is currently '
              'broken/in repair. Fix or resolve it first.');
        }
      }
      units.removeRange(newQuantity, units.length);
    }

    await _collection.doc(equipmentId).set(
      {
        'units': units.map((u) => u.toMap()).toList(),
        'quantity': newQuantity,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// restock/consume a Supply item's on-hand quantity by [delta] (may be
  /// negative). Floors at 0. Read-then-write since we need the current value.
  static Future<void> adjustSupplyQuantity({
    required String equipmentId,
    required int delta,
  }) async {
    final doc = await _collection.doc(equipmentId).get();
    if (!doc.exists) {
      throw Exception('Equipment $equipmentId no longer exists.');
    }
    final data = doc.data();
    if (data?['type'] != EquipmentType.supply) {
      throw Exception('Only Supply items can be restocked this way.');
    }
    final currentQuantity = (data?['quantity'] as num?)?.toInt() ?? 0;
    final newQuantity = math.max(0, currentQuantity + delta);

    await _collection.doc(equipmentId).set(
      {'quantity': newQuantity, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  /// pure helper mirroring [EquipmentItem.isLowStock]; used by the Phase 4
  /// reminder scan so callers don't reach into the model directly.
  static bool computeIsLowStock(EquipmentItem item) => item.isLowStock;

  /// pure client-side filter + sort for the catalog list. Supports a
  /// case-insensitive name query, an optional type filter, and name/quantity
  /// sorts. Status filters (broken/needsService/lowStock) arrive in later
  /// phases; the signature is intentionally extensible.
  static List<EquipmentItem> filterAndSort({
    required List<EquipmentItem> items,
    String query = '',
    String? typeFilter,
    required String sortBy,
  }) {
    final trimmedQuery = query.trim().toLowerCase();
    var result = items.where((item) {
      final matchesQuery = trimmedQuery.isEmpty ||
          item.name.toLowerCase().contains(trimmedQuery);
      final matchesType = typeFilter == null || item.type == typeFilter;
      return matchesQuery && matchesType;
    }).toList();

    switch (sortBy) {
      case 'nameDesc':
        result.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'quantity':
        result.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case 'nameAsc':
      default:
        result.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }
    return result;
  }
}
