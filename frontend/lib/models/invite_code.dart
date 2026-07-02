import 'package:cloud_firestore/cloud_firestore.dart';

/// represents an owner-generated code employees use to self-signup
class InviteCode {
  const InviteCode({
    required this.code,
    required this.active,
    required this.label,
    required this.createdAt,
  });

  final String code;
  final bool active;
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
      active: map['active'] as bool? ?? true,
      label: (map['label'] as String? ?? '').trim(),
      createdAt: createdAt,
    );
  }

  /// convert invite code instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'active': active,
      'label': label,
      'createdAt': createdAt,
    };
  }
}
