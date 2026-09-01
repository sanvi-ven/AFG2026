import 'package:cloud_firestore/cloud_firestore.dart';

/// represents one employee's work-availability marker for a single calendar day
class EmployeeAvailability {
  const EmployeeAvailability({
    required this.id,
    required this.employeeId,
    required this.date,
    this.startTime,
    this.endTime,
  });

  final String id;
  final String employeeId;
  /// yyyy-MM-dd
  final String date;
  /// null start and end together mean "available all day"
  final DateTime? startTime;
  final DateTime? endTime;

  bool get isAllDay => startTime == null && endTime == null;

  /// create availability instance from firestore map data
  factory EmployeeAvailability.fromMap(Map<String, dynamic> map) {
    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return EmployeeAvailability(
      id: (map['id'] as String? ?? '').trim(),
      employeeId: (map['employeeId'] as String? ?? '').trim(),
      date: (map['date'] as String? ?? '').trim(),
      startTime: readDate(map['startTime']),
      endTime: readDate(map['endTime']),
    );
  }

  /// convert availability instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}
