import 'package:cloud_firestore/cloud_firestore.dart';

/// a top-level record of one Equipment unit reserved by an employee for a
/// specific day + time window. Unbounded history + cross-equipment queries
/// ("today's schedule", "my equipment") mean this is a top-level Firestore
/// collection (matching TimeEntry / BrokenReport), not embedded on the parent.
///
/// Reservations are auto-approved — there is no owner-approval queue — but the
/// owner can view and cancel any reservation. [equipmentName] is denormalized
/// so history rows render without a join back to the catalog doc.
class EquipmentReservation {
  const EquipmentReservation({
    required this.id,
    required this.equipmentId,
    required this.equipmentName,
    required this.unitNumber,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.employeeId,
    required this.employeeName,
    this.isCancelled = false,
    this.cancelledAt,
    this.cancelReason = '',
    this.checkedOutAt,
    this.returnedAt,
    this.workId = '',
    this.jobAddress = '',
    this.basketId = '',
    required this.createdAt,
  });

  final String id;
  final String equipmentId;

  /// denormalized display name, so a history row needs no catalog join
  final String equipmentName;
  final int unitNumber;

  /// yyyy-MM-dd of [startTime] — the same-day bucket used for conflict queries
  final String date;
  final DateTime startTime;
  final DateTime endTime;
  final String employeeId;
  final String employeeName;

  final bool isCancelled;
  final DateTime? cancelledAt;
  final String cancelReason;

  /// stamped when the unit is physically checked out (Phase 5 UI)
  final DateTime? checkedOutAt;

  /// stamped when the unit is returned (Phase 5 UI)
  final DateTime? returnedAt;

  /// optional link back to the ScheduledWork this unit is going out with.
  /// Empty means "not linked to a job" — matching the codebase's optional-FK
  /// convention (e.g. ScheduledWork.teamId).
  final String workId;

  /// denormalized job address, so the equipment-side row can show job context
  /// without a lookup — same rationale as [equipmentName].
  final String jobAddress;

  /// optional link back to the EquipmentBasket this reservation was created
  /// as part of. Empty means "not part of a basket" — a standalone
  /// reservation, exactly like every reservation before baskets existed.
  final String basketId;

  final DateTime createdAt;

  bool get isActive => !isCancelled;

  /// true when this reservation is tied to a specific job.
  bool get isLinkedToJob => workId.isNotEmpty;

  /// true when this reservation was created as part of an equipment basket.
  bool get isInBasket => basketId.isNotEmpty;

  /// true when this reservation's window intersects [otherStart]–[otherEnd].
  /// Touching edges (one ends exactly as the other starts) do not overlap.
  bool overlaps(DateTime otherStart, DateTime otherEnd) =>
      startTime.isBefore(otherEnd) && endTime.isAfter(otherStart);

  /// create a reservation from firestore map data
  factory EquipmentReservation.fromMap(Map<String, dynamic> map) {
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

    return EquipmentReservation(
      id: (map['id'] as String? ?? '').trim(),
      equipmentId: (map['equipmentId'] as String? ?? '').trim(),
      equipmentName: (map['equipmentName'] as String? ?? '').trim(),
      unitNumber: (map['unitNumber'] as num?)?.toInt() ?? 0,
      date: (map['date'] as String? ?? '').trim(),
      startTime: readDate(map['startTime']),
      endTime: readDate(map['endTime']),
      employeeId: (map['employeeId'] as String? ?? '').trim(),
      employeeName: (map['employeeName'] as String? ?? '').trim(),
      isCancelled: map['isCancelled'] as bool? ?? false,
      cancelledAt: readNullableDate(map['cancelledAt']),
      cancelReason: (map['cancelReason'] as String? ?? '').trim(),
      checkedOutAt: readNullableDate(map['checkedOutAt']),
      returnedAt: readNullableDate(map['returnedAt']),
      workId: (map['workId'] as String? ?? '').trim(),
      jobAddress: (map['jobAddress'] as String? ?? '').trim(),
      basketId: (map['basketId'] as String? ?? '').trim(),
      createdAt: readDate(map['createdAt']),
    );
  }

  /// convert this reservation to a firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'equipmentId': equipmentId,
      'equipmentName': equipmentName,
      'unitNumber': unitNumber,
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'isCancelled': isCancelled,
      'cancelledAt': cancelledAt,
      'cancelReason': cancelReason,
      'checkedOutAt': checkedOutAt,
      'returnedAt': returnedAt,
      'workId': workId,
      'jobAddress': jobAddress,
      'basketId': basketId,
      'createdAt': createdAt,
    };
  }
}
