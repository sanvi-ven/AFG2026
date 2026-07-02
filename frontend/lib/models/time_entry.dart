import 'package:cloud_firestore/cloud_firestore.dart';

/// represents a single employee's clock in/out record for one calendar day
class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.employeeId,
    required this.date,
    this.clockInAt,
    this.clockOutAt,
  });

  final String id;
  final String employeeId;
  /// yyyy-MM-dd
  final String date;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;

  bool get isClockedIn => clockInAt != null && clockOutAt == null;

  /// create time entry instance from firestore map data
  factory TimeEntry.fromMap(Map<String, dynamic> map) {
    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return TimeEntry(
      id: (map['id'] as String? ?? '').trim(),
      employeeId: (map['employeeId'] as String? ?? '').trim(),
      date: (map['date'] as String? ?? '').trim(),
      clockInAt: readDate(map['clockInAt']),
      clockOutAt: readDate(map['clockOutAt']),
    );
  }

  /// convert time entry instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'date': date,
      'clockInAt': clockInAt,
      'clockOutAt': clockOutAt,
    };
  }
}
