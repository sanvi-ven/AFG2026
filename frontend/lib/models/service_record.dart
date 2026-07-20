import 'package:cloud_firestore/cloud_firestore.dart';

/// a top-level record of one service/maintenance event on a specific Equipment
/// unit (oil change, blade swap, etc.). Unbounded history + cross-equipment
/// queries mean this is a top-level Firestore collection (matching TimeEntry /
/// BrokenReport), not embedded on the parent doc.
///
/// The "next service due" can be entered two ways ([ServiceDueMode]): an
/// explicit calendar date, or an interval in days from the serviced date.
/// Whichever way it's entered, [nextServiceDueDate] is always computed and
/// stored at write time — that's the single field the due-soon check compares
/// against "now".
class ServiceRecord {
  const ServiceRecord({
    required this.id,
    required this.equipmentId,
    required this.unitNumber,
    required this.servicedDate,
    required this.note,
    required this.nextServiceMode,
    this.nextServiceExplicitDate,
    this.nextServiceIntervalDays,
    required this.nextServiceDueDate,
    required this.recordedByRole,
    required this.recordedById,
    required this.recordedByName,
    required this.createdAt,
  });

  final String id;
  final String equipmentId;
  final int unitNumber;
  final DateTime servicedDate;
  final String note;

  /// [ServiceDueMode.explicitDate] or [ServiceDueMode.intervalDays]
  final String nextServiceMode;

  /// set iff [nextServiceMode] == [ServiceDueMode.explicitDate]
  final DateTime? nextServiceExplicitDate;

  /// set iff [nextServiceMode] == [ServiceDueMode.intervalDays]
  final int? nextServiceIntervalDays;

  /// always computed + stored at write time regardless of mode — this is what
  /// the reminder scan compares against "now" for the due-soon check.
  final DateTime nextServiceDueDate;

  /// 'owner' or 'employee' — who logged the service
  final String recordedByRole;
  final String recordedById;
  final String recordedByName;
  final DateTime createdAt;

  /// create a service record from firestore map data
  factory ServiceRecord.fromMap(Map<String, dynamic> map) {
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

    return ServiceRecord(
      id: (map['id'] as String? ?? '').trim(),
      equipmentId: (map['equipmentId'] as String? ?? '').trim(),
      unitNumber: (map['unitNumber'] as num?)?.toInt() ?? 0,
      servicedDate: readDate(map['servicedDate']),
      note: (map['note'] as String? ?? '').trim(),
      nextServiceMode:
          (map['nextServiceMode'] as String? ?? ServiceDueMode.intervalDays)
              .trim(),
      nextServiceExplicitDate: readNullableDate(map['nextServiceExplicitDate']),
      nextServiceIntervalDays:
          (map['nextServiceIntervalDays'] as num?)?.toInt(),
      nextServiceDueDate: readDate(map['nextServiceDueDate']),
      recordedByRole: (map['recordedByRole'] as String? ?? '').trim(),
      recordedById: (map['recordedById'] as String? ?? '').trim(),
      recordedByName: (map['recordedByName'] as String? ?? '').trim(),
      createdAt: readDate(map['createdAt']),
    );
  }

  /// convert this service record to a firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'equipmentId': equipmentId,
      'unitNumber': unitNumber,
      'servicedDate': servicedDate,
      'note': note,
      'nextServiceMode': nextServiceMode,
      'nextServiceExplicitDate': nextServiceExplicitDate,
      'nextServiceIntervalDays': nextServiceIntervalDays,
      'nextServiceDueDate': nextServiceDueDate,
      'recordedByRole': recordedByRole,
      'recordedById': recordedById,
      'recordedByName': recordedByName,
      'createdAt': createdAt,
    };
  }
}

/// plain string constants for how the next service date was entered, matching
/// this codebase's RequestStatus/EquipmentUnitStatus convention.
class ServiceDueMode {
  static const explicitDate = 'explicitDate';
  static const intervalDays = 'intervalDays';
}
