import 'package:cloud_firestore/cloud_firestore.dart';

/// a staff-only note attached to an Estimate or a ScheduledWork job (which
/// covers jobs created via the Quick Add Job dialog too — same entity, just
/// a faster creation path). Stored in its own top-level collection rather
/// than as a field on the estimate/job doc, since firestore.rules grants a
/// client a full document read of their own estimate/scheduled_work record
/// — Firestore security is document-level, not field-level, so a field on
/// that doc would leak to the client regardless of what the UI renders.
/// Append-only (no update) — correcting a note means deleting and
/// reposting; see InternalNoteService.
class InternalNote {
  const InternalNote({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.text,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.createdAt,
  });

  final String id;

  /// [InternalNoteEntityType.estimate] or [InternalNoteEntityType.scheduledWork]
  final String entityType;

  /// Estimate.id or ScheduledWork.id
  final String entityId;

  final String text;

  /// 'owner' sentinel (the owner role has no profile doc/profile_id claim),
  /// or the employee's EmployeeProfile.employeeId
  final String authorId;
  final String authorName;

  /// 'owner' or 'employee' — never 'client'
  final String authorRole;

  final DateTime createdAt;

  factory InternalNote.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return InternalNote(
      id: (map['id'] as String? ?? '').trim(),
      entityType: (map['entityType'] as String? ?? '').trim(),
      entityId: (map['entityId'] as String? ?? '').trim(),
      text: (map['text'] as String? ?? '').trim(),
      authorId: (map['authorId'] as String? ?? '').trim(),
      authorName: (map['authorName'] as String? ?? '').trim(),
      authorRole: (map['authorRole'] as String? ?? '').trim(),
      createdAt: readDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entityType': entityType,
      'entityId': entityId,
      'text': text,
      'authorId': authorId,
      'authorName': authorName,
      'authorRole': authorRole,
      'createdAt': createdAt,
    };
  }
}

/// plain string constants for which kind of record an InternalNote is
/// attached to, matching this codebase's RequestStatus/EquipmentUnitStatus
/// convention.
class InternalNoteEntityType {
  static const estimate = 'estimate';
  static const scheduledWork = 'scheduledWork';
}
