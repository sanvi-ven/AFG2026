import 'package:cloud_firestore/cloud_firestore.dart';

/// represents a business expense (materials, gas, etc.) the owner logs
class Expense {
  const Expense({
    required this.id,
    required this.description,
    required this.category,
    required this.amount,
    required this.date,
    required this.createdAt,
  });

  final String id;
  final String description;
  final String category;
  final double amount;
  final DateTime date;
  final DateTime createdAt;

  /// create expense instance from firestore map data
  factory Expense.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return Expense(
      id: (map['id'] as String? ?? '').trim(),
      description: (map['description'] as String? ?? '').trim(),
      category: (map['category'] as String? ?? ExpenseCategory.other).trim(),
      amount: (map['amount'] as num? ?? 0).toDouble(),
      date: readDate(map['date']),
      createdAt: readDate(map['createdAt']),
    );
  }

  /// convert expense instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'description': description,
      'category': category,
      'amount': amount,
      'date': date,
      'createdAt': createdAt,
    };
  }
}

/// plain string constants for expense categories, matching this codebase's
/// InvoiceStatus/ScheduledWorkStatus convention
class ExpenseCategory {
  static const material = 'material';
  static const gas = 'gas';
  static const other = 'other';
  static const all = [material, gas, other];

  static String displayLabel(String category) {
    final normalized = category.trim().toLowerCase();
    if (normalized.isEmpty) return 'Other';
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}
