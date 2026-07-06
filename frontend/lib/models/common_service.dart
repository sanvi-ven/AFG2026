import 'package:cloud_firestore/cloud_firestore.dart';

/// a saved, reusable service line item the owner can search for while
/// building an estimate instead of retyping it from scratch
class CommonService {
  const CommonService({
    required this.id,
    required this.name,
    required this.description,
    this.unit,
    this.unitPrice,
    this.flatPrice,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  /// price per [unit] (e.g. $1 per foot); null means this catalog entry is flat-fee
  final String? unit;
  final double? unitPrice;
  final double? flatPrice;
  final DateTime createdAt;

  bool get isPerUnit => unitPrice != null;

  /// create catalog entry from firestore map data
  factory CommonService.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return CommonService(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      description: (map['description'] as String? ?? '').trim(),
      unit: (map['unit'] as String?)?.trim(),
      unitPrice: (map['unitPrice'] as num?)?.toDouble(),
      flatPrice: (map['flatPrice'] as num?)?.toDouble(),
      createdAt: readDate(map['createdAt']),
    );
  }

  /// convert catalog entry to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'unit': unit,
      'unitPrice': unitPrice,
      'flatPrice': flatPrice,
      'createdAt': createdAt,
    };
  }
}
