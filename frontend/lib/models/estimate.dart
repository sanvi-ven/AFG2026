import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice.dart';

class Estimate {
  const Estimate({
    required this.id,
    required this.estimateNumber,
    required this.clientId,
    required this.services,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.convertedToInvoice,
    this.convertedInvoiceId,
    this.convertedAt,
  });

  final String id;
  final String estimateNumber;
  final String clientId;
  final List<InvoiceServiceItem> services;
  final double total;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool convertedToInvoice;
  final String? convertedInvoiceId;
  final DateTime? convertedAt;

  bool get isPending => status == InvoiceStatus.pending;
  bool get isApproved => status == InvoiceStatus.approved;
  bool get isDenied => status == InvoiceStatus.denied;
  bool get isConvertible => isApproved && !convertedToInvoice;

  factory Estimate.fromMap(Map<String, dynamic> map) {
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
      if (value == null) {
        return null;
      }
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return Estimate(
      id: (map['id'] as String? ?? '').trim(),
      estimateNumber: (map['estimateNumber'] as String? ?? '').trim(),
      clientId: (map['clientId'] as String? ?? '').trim(),
      services: serviceRows,
      total: (map['total'] as num? ?? 0).toDouble(),
      status: (map['status'] as String? ?? InvoiceStatus.pending).trim(),
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
      convertedToInvoice: map['convertedToInvoice'] as bool? ?? false,
      convertedInvoiceId: (map['convertedInvoiceId'] as String?)?.trim(),
      convertedAt: readOptionalDate(map['convertedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'estimateNumber': estimateNumber,
      'clientId': clientId,
      'services': services.map((item) => item.toMap()).toList(),
      'total': total,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'convertedToInvoice': convertedToInvoice,
      'convertedInvoiceId': convertedInvoiceId,
      'convertedAt': convertedAt,
    };
  }
}
