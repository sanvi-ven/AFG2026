import 'package:cloud_firestore/cloud_firestore.dart';

/// represents the one-time completion report a crew member files for a job
class JobCompletionForm {
  const JobCompletionForm({
    required this.workId,
    required this.teamId,
    required this.submittedByEmployeeId,
    required this.submittedByName,
    required this.startTime,
    required this.endTime,
    required this.notes,
    required this.beforePhotoUrls,
    required this.afterPhotoUrls,
    required this.createdAt,
  });

  final String workId;
  final String? teamId;
  final String submittedByEmployeeId;
  final String submittedByName;
  final DateTime startTime;
  final DateTime endTime;
  final String notes;
  final List<String> beforePhotoUrls;
  final List<String> afterPhotoUrls;
  final DateTime createdAt;

  /// create job completion form instance from firestore map data
  factory JobCompletionForm.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    final rawTeamId = (map['teamId'] as String? ?? '').trim();

    return JobCompletionForm(
      workId: (map['workId'] as String? ?? '').trim(),
      teamId: rawTeamId.isEmpty ? null : rawTeamId,
      submittedByEmployeeId: (map['submittedByEmployeeId'] as String? ?? '').trim(),
      submittedByName: (map['submittedByName'] as String? ?? '').trim(),
      startTime: readDate(map['startTime']),
      endTime: readDate(map['endTime']),
      notes: (map['notes'] as String? ?? '').trim(),
      beforePhotoUrls: (map['beforePhotoUrls'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      afterPhotoUrls: (map['afterPhotoUrls'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      createdAt: readDate(map['createdAt']),
    );
  }

  /// convert job completion form instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'workId': workId,
      'teamId': teamId,
      'submittedByEmployeeId': submittedByEmployeeId,
      'submittedByName': submittedByName,
      'startTime': startTime,
      'endTime': endTime,
      'notes': notes,
      'beforePhotoUrls': beforePhotoUrls,
      'afterPhotoUrls': afterPhotoUrls,
      'createdAt': createdAt,
    };
  }
}
