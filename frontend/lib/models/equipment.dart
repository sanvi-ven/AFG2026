import 'package:cloud_firestore/cloud_firestore.dart';

/// a catalog entry for a physical asset the business owns — either durable
/// [EquipmentType.equipment] (tracked as numbered units, requestable) or a
/// consumable [EquipmentType.supply] (a running quantity with a low-stock
/// threshold, no units). Both types share catalog CRUD, photos, and one
/// browsable list; only the UI branches on [type].
class EquipmentItem {
  const EquipmentItem({
    required this.id,
    required this.type,
    required this.name,
    this.photoUrls = const [],
    this.quantity = 1,
    this.unitOfMeasure = '',
    this.lowStockThreshold,
    this.lowStockManualFlag = false,
    this.lowStockNotifiedAt,
    this.defaultServiceIntervalDays,
    this.units = const [],
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// [EquipmentType.equipment] or [EquipmentType.supply]
  final String type;
  final String name;
  final List<String> photoUrls;

  /// total unit count for Equipment, on-hand count for Supply
  final int quantity;

  /// Supply only (e.g. "boxes", "L"); empty string for Equipment
  final String unitOfMeasure;

  /// Supply only — at/below this on-hand count the item reads as low stock
  final int? lowStockThreshold;

  /// owner can manually flag an item as low regardless of threshold
  final bool lowStockManualFlag;

  /// stamped when a low-stock reminder was last sent (dedupe, Phase 4)
  final DateTime? lowStockNotifiedAt;

  /// Equipment only — convenience default when logging service on a unit
  final int? defaultServiceIntervalDays;

  /// Equipment only — one entry per physical unit (1..quantity); empty for
  /// Supply. Unit status transitions arrive in Phase 2; this phase only
  /// creates units with [EquipmentUnitStatus.active].
  final List<EquipmentUnit> units;

  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSupply => type == EquipmentType.supply;
  bool get isEquipment => type == EquipmentType.equipment;

  bool get isLowStock =>
      lowStockManualFlag ||
      (lowStockThreshold != null && quantity <= lowStockThreshold!);

  /// create an equipment instance from firestore map data
  factory EquipmentItem.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? readNullableDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return EquipmentItem(
      id: (map['id'] as String? ?? '').trim(),
      type: (map['type'] as String? ?? EquipmentType.equipment).trim(),
      name: (map['name'] as String? ?? '').trim(),
      photoUrls: (map['photoUrls'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      unitOfMeasure: (map['unitOfMeasure'] as String? ?? '').trim(),
      lowStockThreshold: (map['lowStockThreshold'] as num?)?.toInt(),
      lowStockManualFlag: map['lowStockManualFlag'] as bool? ?? false,
      lowStockNotifiedAt: readNullableDate(map['lowStockNotifiedAt']),
      defaultServiceIntervalDays:
          (map['defaultServiceIntervalDays'] as num?)?.toInt(),
      units: (map['units'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(EquipmentUnit.fromMap)
          .toList(),
      isArchived: map['isArchived'] as bool? ?? false,
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
    );
  }

  /// convert this equipment instance to a firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'photoUrls': photoUrls,
      'quantity': quantity,
      'unitOfMeasure': unitOfMeasure,
      'lowStockThreshold': lowStockThreshold,
      'lowStockManualFlag': lowStockManualFlag,
      'lowStockNotifiedAt': lowStockNotifiedAt,
      'defaultServiceIntervalDays': defaultServiceIntervalDays,
      'units': units.map((u) => u.toMap()).toList(),
      'isArchived': isArchived,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

/// a single physical unit of an Equipment item, embedded on the parent doc
/// (bounded, always co-read with its parent). Not a Firestore doc of its own,
/// so it has no top-level id.
class EquipmentUnit {
  const EquipmentUnit({
    required this.unitNumber,
    this.status = EquipmentUnitStatus.active,
    this.currentBrokenReportId,
    this.lastServiceDate,
    this.nextServiceDueDate,
    this.serviceIntervalDays,
    this.serviceDueSnoozedUntil,
    this.serviceDueNotifiedAt,
  });

  final int unitNumber;

  /// [EquipmentUnitStatus] — only `active` is used until Phase 2
  final String status;
  final String? currentBrokenReportId;
  final DateTime? lastServiceDate;
  final DateTime? nextServiceDueDate;
  final int? serviceIntervalDays;
  final DateTime? serviceDueSnoozedUntil;
  final DateTime? serviceDueNotifiedAt;

  factory EquipmentUnit.fromMap(Map<String, dynamic> map) {
    DateTime? readNullableDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return EquipmentUnit(
      unitNumber: (map['unitNumber'] as num?)?.toInt() ?? 0,
      status: (map['status'] as String? ?? EquipmentUnitStatus.active).trim(),
      currentBrokenReportId:
          (map['currentBrokenReportId'] as String?)?.trim().isEmpty ?? true
              ? null
              : (map['currentBrokenReportId'] as String).trim(),
      lastServiceDate: readNullableDate(map['lastServiceDate']),
      nextServiceDueDate: readNullableDate(map['nextServiceDueDate']),
      serviceIntervalDays: (map['serviceIntervalDays'] as num?)?.toInt(),
      serviceDueSnoozedUntil: readNullableDate(map['serviceDueSnoozedUntil']),
      serviceDueNotifiedAt: readNullableDate(map['serviceDueNotifiedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'unitNumber': unitNumber,
      'status': status,
      'currentBrokenReportId': currentBrokenReportId,
      'lastServiceDate': lastServiceDate,
      'nextServiceDueDate': nextServiceDueDate,
      'serviceIntervalDays': serviceIntervalDays,
      'serviceDueSnoozedUntil': serviceDueSnoozedUntil,
      'serviceDueNotifiedAt': serviceDueNotifiedAt,
    };
  }
}

/// plain string constants for equipment type, matching this codebase's
/// RequestStatus/ScheduledWorkStatus convention
class EquipmentType {
  static const equipment = 'equipment';
  static const supply = 'supply';
}

/// plain string constants for a unit's lifecycle status. Only `active` is used
/// in Phase 1; `broken`/`inRepair` land in Phase 2.
class EquipmentUnitStatus {
  static const active = 'active';
  static const broken = 'broken';
  static const inRepair = 'inRepair';
}

/// how far ahead a unit's next-service date counts as "due soon." Shared by
/// ReminderCheckService (which fires the notification) and the equipment
/// detail page (which shows the badge), so the two can't silently drift apart.
const Duration equipmentServiceDueLeadTime = Duration(days: 14);
