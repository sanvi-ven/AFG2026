import 'package:cloud_firestore/cloud_firestore.dart';

/// represents a named crew that employees can be assigned to
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// create team instance from firestore map data
  factory Team.fromMap(Map<String, dynamic> map) {
    final rawCreatedAt = map['createdAt'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : (rawCreatedAt is String ? DateTime.tryParse(rawCreatedAt) : null) ?? DateTime.now();

    return Team(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      createdAt: createdAt,
    );
  }

  /// convert team instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
    };
  }
}
