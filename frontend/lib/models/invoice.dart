import 'package:cloud_firestore/cloud_firestore.dart';

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

  bool get isPending => status == InvoiceStatus.pending;
  bool get isApproved => InvoiceStatus.isSent(status);
  bool get isDenied => status == InvoiceStatus.denied;

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
    };
  }
}

class InvoiceServiceItem {
  const InvoiceServiceItem({
    required this.name,
    required this.price,
  });

  final String name;
  final double price;

  factory InvoiceServiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceServiceItem(
      name: (map['name'] as String? ?? '').trim(),
      price: (map['price'] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
    };
  }
}

class InvoiceStatus {
  static const pending = 'pending';
  static const sent = 'sent';
  // Kept for backwards compatibility with legacy invoice documents.
  static const approved = 'approved';
  static const denied = 'denied';
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
