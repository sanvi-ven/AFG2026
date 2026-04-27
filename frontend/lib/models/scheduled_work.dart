import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice.dart';

class ScheduledWork {
  const ScheduledWork({
    required this.id,
    required this.estimateId,
    required this.estimateNumber,
    required this.clientId,
    required this.services,
    required this.total,
    required this.scheduledDate,
    required this.status,
    this.invoiceId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String estimateId;
  final String estimateNumber;
  final String clientId;
  final List<InvoiceServiceItem> services;
  final double total;
  final DateTime scheduledDate;
  final String status;
  final String? invoiceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isScheduled => status == ScheduledWorkStatus.scheduled;
  bool get isCompleted => status == ScheduledWorkStatus.completed;
  bool get isInvoiced => status == ScheduledWorkStatus.invoiced;

  factory ScheduledWork.fromMap(Map<String, dynamic> map) {
    final serviceRows = (map['services'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(InvoiceServiceItem.fromMap)
        .toList();

    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return ScheduledWork(
      id: (map['id'] as String? ?? '').trim(),
      estimateId: (map['estimateId'] as String? ?? '').trim(),
      estimateNumber: (map['estimateNumber'] as String? ?? '').trim(),
      clientId: (map['clientId'] as String? ?? '').trim(),
      services: serviceRows,
      total: (map['total'] as num? ?? 0).toDouble(),
      scheduledDate: readDate(map['scheduledDate']),
      status: (map['status'] as String? ?? ScheduledWorkStatus.scheduled).trim(),
      invoiceId: (map['invoiceId'] as String?)?.trim(),
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'estimateId': estimateId,
      'estimateNumber': estimateNumber,
      'clientId': clientId,
      'services': services.map((item) => item.toMap()).toList(),
      'total': total,
      'scheduledDate': scheduledDate,
      'status': status,
      'invoiceId': invoiceId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class ScheduledWorkStatus {
  static const scheduled = 'scheduled';
  static const completed = 'completed';
  static const invoiced = 'invoiced';
}
