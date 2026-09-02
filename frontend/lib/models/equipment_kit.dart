import 'package:cloud_firestore/cloud_firestore.dart';

/// a saved, reusable preset list of equipment/supplies (e.g. "Mowing setup",
/// "Leaf cleanup setup") that a basket can be started from — picking a kit
/// pre-fills a basket's lines with [items], which the basket screen then
/// lets the user adjust before submitting. Staff-shared: any owner or
/// employee can create, edit, or delete any kit (matches this app's existing
/// equipment/teams "full parity" design), so there's no createdBy-based
/// permission check — [createdByName] is display-only.
class EquipmentKit {
  const EquipmentKit({
    required this.id,
    required this.name,
    this.description = '',
    this.items = const [],
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final List<EquipmentKitItem> items;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory EquipmentKit.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return EquipmentKit(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      description: (map['description'] as String? ?? '').trim(),
      items: (map['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(EquipmentKitItem.fromMap)
          .toList(),
      createdByName: (map['createdByName'] as String? ?? '').trim(),
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'items': items.map((i) => i.toMap()).toList(),
      'createdByName': createdByName,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

/// one line in a kit — a specific catalog item (equipment or supply) and the
/// default quantity a basket started from this kit should pre-fill. [type]
/// mirrors [EquipmentType] so the basket builder can tell, without a catalog
/// lookup, whether a line belongs on the equipment side (reservable, per-unit)
/// or the supply side (consumable, quantity-only) if the catalog item is
/// later archived and can't be resolved.
class EquipmentKitItem {
  const EquipmentKitItem({
    required this.equipmentId,
    required this.name,
    required this.type,
    required this.quantity,
  });

  final String equipmentId;
  final String name;
  final String type;
  final int quantity;

  factory EquipmentKitItem.fromMap(Map<String, dynamic> map) {
    return EquipmentKitItem(
      equipmentId: (map['equipmentId'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      type: (map['type'] as String? ?? '').trim(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'equipmentId': equipmentId,
      'name': name,
      'type': type,
      'quantity': quantity,
    };
  }
}
