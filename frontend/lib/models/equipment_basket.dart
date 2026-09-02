import 'package:cloud_firestore/cloud_firestore.dart';

import 'equipment_reservation.dart';

/// a set of equipment + supplies reserved together for one shared time
/// window, so it can be checked out and returned as a single action instead
/// of one item at a time. The equipment side of a basket is still one
/// [EquipmentReservation] doc per unit (matching how single-item reservations
/// already work) — this doc just groups them via [EquipmentReservation.basketId]
/// and carries the consumable side ([supplyLines]), which has no per-unit /
/// time-conflict concept and so never gets its own reservation docs.
class EquipmentBasket {
  const EquipmentBasket({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.employeeId,
    required this.employeeName,
    this.workId = '',
    this.jobAddress = '',
    this.kitId = '',
    this.kitName = '',
    this.supplyLines = const [],
    this.isCancelled = false,
    this.cancelledAt,
    this.cancelReason = '',
    required this.createdAt,
  });

  final String id;

  /// yyyy-MM-dd of [startTime] — same-day bucket, matching EquipmentReservation.
  final String date;
  final DateTime startTime;
  final DateTime endTime;
  final String employeeId;
  final String employeeName;

  /// optional link back to the job this basket's gear is going out with.
  final String workId;
  final String jobAddress;

  /// optional link back to the EquipmentKit this basket was started from —
  /// empty means it was built from scratch.
  final String kitId;
  final String kitName;

  final List<EquipmentBasketSupplyLine> supplyLines;

  final bool isCancelled;
  final DateTime? cancelledAt;
  final String cancelReason;

  final DateTime createdAt;

  bool get isActive => !isCancelled;
  bool get isLinkedToJob => workId.isNotEmpty;
  bool get startedFromKit => kitId.isNotEmpty;

  factory EquipmentBasket.fromMap(Map<String, dynamic> map) {
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

    return EquipmentBasket(
      id: (map['id'] as String? ?? '').trim(),
      date: (map['date'] as String? ?? '').trim(),
      startTime: readDate(map['startTime']),
      endTime: readDate(map['endTime']),
      employeeId: (map['employeeId'] as String? ?? '').trim(),
      employeeName: (map['employeeName'] as String? ?? '').trim(),
      workId: (map['workId'] as String? ?? '').trim(),
      jobAddress: (map['jobAddress'] as String? ?? '').trim(),
      kitId: (map['kitId'] as String? ?? '').trim(),
      kitName: (map['kitName'] as String? ?? '').trim(),
      supplyLines: (map['supplyLines'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(EquipmentBasketSupplyLine.fromMap)
          .toList(),
      isCancelled: map['isCancelled'] as bool? ?? false,
      cancelledAt: readNullableDate(map['cancelledAt']),
      cancelReason: (map['cancelReason'] as String? ?? '').trim(),
      createdAt: readDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'workId': workId,
      'jobAddress': jobAddress,
      'kitId': kitId,
      'kitName': kitName,
      'supplyLines': supplyLines.map((s) => s.toMap()).toList(),
      'isCancelled': isCancelled,
      'cancelledAt': cancelledAt,
      'cancelReason': cancelReason,
      'createdAt': createdAt,
    };
  }

  /// derives a basket's overall status from its live children — never stored,
  /// so it can't go stale relative to the reservations/supply lines it
  /// summarizes. [reservations] should already be filtered to this basket's
  /// own [EquipmentReservation.basketId].
  String computeStatus(List<EquipmentReservation> reservations) {
    if (isCancelled) return EquipmentBasketStatus.cancelled;

    final activeReservations = reservations.where((r) => r.isActive).toList();
    final totalLines = activeReservations.length + supplyLines.length;
    if (totalLines == 0) return EquipmentBasketStatus.reserved;

    final checkedOutCount =
        activeReservations.where((r) => r.checkedOutAt != null).length +
            supplyLines.where((s) => s.consumedAt != null).length;

    if (checkedOutCount == 0) return EquipmentBasketStatus.reserved;

    if (activeReservations.isNotEmpty) {
      final returnedCount =
          activeReservations.where((r) => r.returnedAt != null).length;
      if (returnedCount == activeReservations.length) {
        return EquipmentBasketStatus.returned;
      }
      if (returnedCount > 0) return EquipmentBasketStatus.partiallyReturned;
    }

    if (checkedOutCount == totalLines) return EquipmentBasketStatus.checkedOut;
    return EquipmentBasketStatus.partiallyCheckedOut;
  }
}

/// one consumable line embedded on a basket — a supply item + quantity taken
/// out of stock. No per-unit identity and no "return": once [consumedAt] is
/// stamped (at basket check-out), the on-hand [EquipmentItem.quantity] has
/// already been decremented for good.
class EquipmentBasketSupplyLine {
  const EquipmentBasketSupplyLine({
    required this.equipmentId,
    required this.name,
    required this.quantity,
    this.unitOfMeasure = '',
    this.consumedAt,
  });

  final String equipmentId;
  final String name;
  final int quantity;
  final String unitOfMeasure;
  final DateTime? consumedAt;

  EquipmentBasketSupplyLine copyWith({DateTime? consumedAt}) {
    return EquipmentBasketSupplyLine(
      equipmentId: equipmentId,
      name: name,
      quantity: quantity,
      unitOfMeasure: unitOfMeasure,
      consumedAt: consumedAt ?? this.consumedAt,
    );
  }

  factory EquipmentBasketSupplyLine.fromMap(Map<String, dynamic> map) {
    DateTime? readNullableDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return EquipmentBasketSupplyLine(
      equipmentId: (map['equipmentId'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitOfMeasure: (map['unitOfMeasure'] as String? ?? '').trim(),
      consumedAt: readNullableDate(map['consumedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'equipmentId': equipmentId,
      'name': name,
      'quantity': quantity,
      'unitOfMeasure': unitOfMeasure,
      'consumedAt': consumedAt,
    };
  }
}

/// plain string constants for a basket's derived status (see
/// [EquipmentBasket.computeStatus]).
class EquipmentBasketStatus {
  static const reserved = 'reserved';
  static const partiallyCheckedOut = 'partiallyCheckedOut';
  static const checkedOut = 'checkedOut';
  static const partiallyReturned = 'partiallyReturned';
  static const returned = 'returned';
  static const cancelled = 'cancelled';
}
