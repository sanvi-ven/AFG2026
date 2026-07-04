import 'package:cloud_firestore/cloud_firestore.dart';

/// represents an owner-generated code employees use to self-signup.
/// deleting a code is the only lifecycle action — existence in Firestore
/// is what makes it valid, so there's no separate active/inactive state.
class InviteCode {
  const InviteCode({
    required this.code,
    required this.label,
    required this.createdAt,
  });

  final String code;
  final String label;
  final DateTime createdAt;

  /// create invite code instance from firestore map data
  factory InviteCode.fromMap(Map<String, dynamic> map) {
    final rawCreatedAt = map['createdAt'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : (rawCreatedAt is String ? DateTime.tryParse(rawCreatedAt) : null) ?? DateTime.now();

    return InviteCode(
      code: (map['code'] as String? ?? '').trim(),
      label: (map['label'] as String? ?? '').trim(),
      createdAt: createdAt,
    );
  }

  /// convert invite code instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'label': label,
      'createdAt': createdAt,
    };
  }
}
