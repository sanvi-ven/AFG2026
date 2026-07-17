import 'package:cloud_firestore/cloud_firestore.dart';

/// represents an invoice with services items and payment status
class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.clientId,
    required this.services,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sourceEstimateId,
    this.isArchived = false,
    this.notes = '',
    this.terms = '',
    this.lastReminderSentAt,
  });

  final String id;
  final String invoiceNumber;
  final String clientId;
  final List<InvoiceServiceItem> services;
  final double total;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourceEstimateId;
  final bool isArchived;
  final String notes;
  final String terms;
  /// when an overdue-invoice reminder notification was last created; null
  /// means none has been sent yet
  final DateTime? lastReminderSentAt;

  bool get isPending => status == InvoiceStatus.pending;
  bool get isApproved => InvoiceStatus.isSent(status);
  bool get isDenied => status == InvoiceStatus.denied;

  /// create invoice from firestore map data
  factory Invoice.fromMap(Map<String, dynamic> map) {
    final serviceRows = (map['services'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(InvoiceServiceItem.fromMap)
        .toList();

    DateTime readDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    DateTime? readOptionalDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return Invoice(
      id: (map['id'] as String? ?? '').trim(),
      invoiceNumber: (map['invoiceNumber'] as String? ?? '').trim(),
      clientId: (map['clientId'] as String? ?? '').trim(),
      services: serviceRows,
      total: (map['total'] as num? ?? 0).toDouble(),
      status: (map['status'] as String? ?? InvoiceStatus.pending).trim(),
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
      sourceEstimateId: (map['sourceEstimateId'] as String?)?.trim(),
      isArchived: map['archived'] as bool? ?? false,
      notes: (map['notes'] as String? ?? '').trim(),
      terms: (map['terms'] as String? ?? '').trim(),
      lastReminderSentAt: readOptionalDate(map['lastReminderSentAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoiceNumber': invoiceNumber,
      'clientId': clientId,
      'services': services.map((item) => item.toMap()).toList(),
      'total': total,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sourceEstimateId': sourceEstimateId,
      'archived': isArchived,
      'notes': notes,
      'terms': terms,
      'lastReminderSentAt': lastReminderSentAt,
    };
  }
}

class InvoiceServiceItem {
  const InvoiceServiceItem({
    required this.name,
    required this.price,
    this.description = '',
    this.unitPrice,
    this.quantity,
    this.unit,
  });

  final String name;
  final double price;
  final String description;
  /// price per [unit] (e.g. $1 per foot); null means [price] is a flat fee
  final double? unitPrice;
  final double? quantity;
  final String? unit;

  bool get isPerUnit => unitPrice != null && quantity != null;

  /// create service item from firestore map
  factory InvoiceServiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceServiceItem(
      name: (map['name'] as String? ?? '').trim(),
      price: (map['price'] as num? ?? 0).toDouble(),
      description: (map['description'] as String? ?? '').trim(),
      unitPrice: (map['unitPrice'] as num?)?.toDouble(),
      quantity: (map['quantity'] as num?)?.toDouble(),
      unit: (map['unit'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'description': description,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'unit': unit,
    };
  }
}

class InvoiceStatus {
  static const pending = 'pending';
  static const sent = 'sent';
  // Kept for backwards compatibility with legacy invoice documents.
  static const approved = 'approved';
  static const denied = 'denied';
  static const changesRequested = 'changes_requested';
  static const paid = 'paid';

  static bool isSent(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == sent || normalized == approved;
  }

  static String displayLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (isSent(normalized)) {
      return sent;
    }
    if (normalized.isEmpty) {
      return pending;
    }
    return normalized;
  }
}
