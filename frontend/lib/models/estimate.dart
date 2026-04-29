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
    this.isScheduled = false,
    this.scheduledWorkId,
    this.revisionNumber = 1,
    this.changeRequestMessage,
    this.changeRequestedAt,
    this.resentAt,
    this.originalVersion,
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
  final bool isScheduled;
  final String? scheduledWorkId;
  final int revisionNumber;
  final String? changeRequestMessage;
  final DateTime? changeRequestedAt;
  final DateTime? resentAt;
  final EstimateVersionSnapshot? originalVersion;

  bool get isPending => status == InvoiceStatus.pending;
  bool get isApproved => status == InvoiceStatus.approved;
  bool get isDenied => status == InvoiceStatus.denied;
  bool get isChangesRequested => status == InvoiceStatus.changesRequested;
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
      isScheduled: map['isScheduled'] as bool? ?? false,
      scheduledWorkId: (map['scheduledWorkId'] as String?)?.trim(),
      revisionNumber: (map['revisionNumber'] as num?)?.toInt() ?? 1,
      changeRequestMessage: (map['changeRequestMessage'] as String?)?.trim(),
      changeRequestedAt: readOptionalDate(map['changeRequestedAt']),
      resentAt: readOptionalDate(map['resentAt']),
      originalVersion: map['originalVersion'] is Map
          ? EstimateVersionSnapshot.fromMap(
              (map['originalVersion'] as Map<dynamic, dynamic>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
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
      'isScheduled': isScheduled,
      'scheduledWorkId': scheduledWorkId,
      'revisionNumber': revisionNumber,
      'changeRequestMessage': changeRequestMessage,
      'changeRequestedAt': changeRequestedAt,
      'resentAt': resentAt,
      'originalVersion': originalVersion?.toMap(),
    };
  }
}

class EstimateVersionSnapshot {
  const EstimateVersionSnapshot({
    required this.version,
    required this.services,
    required this.total,
    required this.status,
    required this.updatedAt,
  });

  final int version;
  final List<InvoiceServiceItem> services;
  final double total;
  final String status;
  final DateTime updatedAt;

  factory EstimateVersionSnapshot.fromMap(Map<String, dynamic> map) {
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

    return EstimateVersionSnapshot(
      version: (map['version'] as num?)?.toInt() ?? 1,
      services: serviceRows,
      total: (map['total'] as num? ?? 0).toDouble(),
      status: (map['status'] as String? ?? InvoiceStatus.pending).trim(),
      updatedAt: readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'services': services.map((item) => item.toMap()).toList(),
      'total': total,
      'status': status,
      'updatedAt': updatedAt,
    };
  }
}
