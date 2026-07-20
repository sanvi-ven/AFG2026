import 'package:cloud_firestore/cloud_firestore.dart';

/// a top-level record of one broken incident on a specific Equipment unit.
/// Unbounded history + cross-equipment "what's broken right now" queries mean
/// this is a top-level Firestore collection (matching TimeEntry), not embedded.
/// Repair attempts are bounded and embedded on this doc as [RepairAttempt]s.
class BrokenReport {
  const BrokenReport({
    required this.id,
    required this.equipmentId,
    required this.unitNumber,
    required this.note,
    required this.reportedByEmployeeId,
    required this.reportedByEmployeeName,
    required this.reportedAt,
    this.status = BrokenReportStatus.open,
    this.resolvedAt,
    this.resolvedNote = '',
    this.repairAttempts = const [],
  });

  final String id;
  final String equipmentId;
  final int unitNumber;
  final String note;
  final String reportedByEmployeeId;
  final String reportedByEmployeeName;
  final DateTime reportedAt;

  /// [BrokenReportStatus.open] or [BrokenReportStatus.repaired]
  final String status;
  final DateTime? resolvedAt;
  final String resolvedNote;
  final List<RepairAttempt> repairAttempts;

  bool get isOpen => status == BrokenReportStatus.open;

  /// create a broken report from firestore map data
  factory BrokenReport.fromMap(Map<String, dynamic> map) {
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

    return BrokenReport(
      id: (map['id'] as String? ?? '').trim(),
      equipmentId: (map['equipmentId'] as String? ?? '').trim(),
      unitNumber: (map['unitNumber'] as num?)?.toInt() ?? 0,
      note: (map['note'] as String? ?? '').trim(),
      reportedByEmployeeId: (map['reportedByEmployeeId'] as String? ?? '').trim(),
      reportedByEmployeeName:
          (map['reportedByEmployeeName'] as String? ?? '').trim(),
      reportedAt: readDate(map['reportedAt']),
      status: (map['status'] as String? ?? BrokenReportStatus.open).trim(),
      resolvedAt: readNullableDate(map['resolvedAt']),
      resolvedNote: (map['resolvedNote'] as String? ?? '').trim(),
      repairAttempts: (map['repairAttempts'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(RepairAttempt.fromMap)
          .toList(),
    );
  }

  /// convert this broken report to a firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'equipmentId': equipmentId,
      'unitNumber': unitNumber,
      'note': note,
      'reportedByEmployeeId': reportedByEmployeeId,
      'reportedByEmployeeName': reportedByEmployeeName,
      'reportedAt': reportedAt,
      'status': status,
      'resolvedAt': resolvedAt,
      'resolvedNote': resolvedNote,
      'repairAttempts': repairAttempts.map((a) => a.toMap()).toList(),
    };
  }
}

/// one repair attempt logged against a [BrokenReport], embedded on the parent
/// doc (bounded, always co-read with its parent). Not a Firestore doc of its
/// own — plain nested map, like EquipmentUnit.
class RepairAttempt {
  const RepairAttempt({
    required this.note,
    required this.employeeId,
    required this.employeeName,
    required this.attemptedAt,
  });

  final String note;
  final String employeeId;
  final String employeeName;
  final DateTime attemptedAt;

  factory RepairAttempt.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return RepairAttempt(
      note: (map['note'] as String? ?? '').trim(),
      employeeId: (map['employeeId'] as String? ?? '').trim(),
      employeeName: (map['employeeName'] as String? ?? '').trim(),
      attemptedAt: readDate(map['attemptedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'note': note,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'attemptedAt': attemptedAt,
    };
  }
}

/// plain string constants for a broken report's lifecycle status, matching
/// this codebase's RequestStatus/EquipmentUnitStatus convention.
class BrokenReportStatus {
  static const open = 'open';
  static const repaired = 'repaired';
}
