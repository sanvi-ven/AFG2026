import 'package:cloud_firestore/cloud_firestore.dart';

/// represents a single employee's clock in/out record for one calendar day
class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.employeeId,
    required this.date,
    this.clockInAt,
    this.clockOutAt,
    this.wageOverride,
    this.notes = '',
    this.isPaid = false,
  });

  final String id;
  final String employeeId;
  /// yyyy-MM-dd
  final String date;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  /// this shift's hourly rate; null means "use the employee's normal hourlyRate"
  final double? wageOverride;
  final String notes;
  final bool isPaid;

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
      wageOverride: (map['wageOverride'] as num?)?.toDouble(),
      notes: (map['notes'] as String? ?? '').trim(),
      isPaid: map['isPaid'] as bool? ?? false,
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
      'wageOverride': wageOverride,
      'notes': notes,
      'isPaid': isPaid,
    };
  }
}
