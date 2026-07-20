import 'package:cloud_firestore/cloud_firestore.dart';

import 'checklist_template.dart';
import 'invoice.dart';

/// represents scheduled work orders from approved estimates
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
    this.teamId,
    this.employeeIds = const [],
    this.address = '',
    this.phoneNumber = '',
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    this.recurringGroupId,
    this.reminderSentAt,
    this.checklistItems = const [],
    this.routeOrder,
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
  /// crew assigned to work this job; null means unassigned
  final String? teamId;
  /// individual employees assigned to this job; mutually exclusive with
  /// [teamId] — assigning one clears the other
  final List<String> employeeIds;
  /// job-site address, denormalized from the client's profile at creation time
  /// so employee screens never need to read the client_signups collection
  final String address;
  /// job-site contact number, denormalized for the same reason as [address]
  final String phoneNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  /// shared id stamped on every job created in one recurring-schedule batch;
  /// null for a one-off job
  final String? recurringGroupId;
  /// when an upcoming-appointment reminder notification was last created for
  /// this job; null means none has been sent yet
  final DateTime? reminderSentAt;
  /// snapshot of a ChecklistTemplate's items (if one was picked when this job
  /// was scheduled); empty means no checklist attached
  final List<ChecklistItem> checklistItems;
  /// owner-set position of this job within its team's route for the day;
  /// null means "not yet manually sequenced" — falls back to scheduledDate order
  final int? routeOrder;

  /// check if this work is scheduled
  bool get isScheduled => status == ScheduledWorkStatus.scheduled;
  /// check if this work is completed
  bool get isCompleted => status == ScheduledWorkStatus.completed;
  /// check if this work has been invoiced
  bool get isInvoiced => status == ScheduledWorkStatus.invoiced;

  /// create scheduled work instance from firestore map data
  factory ScheduledWork.fromMap(Map<String, dynamic> map) {
    final serviceRows = (map['services'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(InvoiceServiceItem.fromMap)
        .toList();

    // helper to parse date from timestamp or string
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? readOptionalDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
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
      teamId: (map['teamId'] as String?)?.trim().isEmpty ?? true ? null : (map['teamId'] as String).trim(),
      employeeIds: (map['employeeIds'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      address: (map['address'] as String? ?? '').trim(),
      phoneNumber: (map['phoneNumber'] as String? ?? '').trim(),
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
      isArchived: map['archived'] as bool? ?? false,
      recurringGroupId: (map['recurringGroupId'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['recurringGroupId'] as String).trim(),
      reminderSentAt: readOptionalDate(map['reminderSentAt']),
      checklistItems: (map['checklistItems'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ChecklistItem.fromMap)
          .toList(),
      routeOrder: (map['routeOrder'] as num?)?.toInt(),
    );
  }

  /// convert scheduled work instance to firestore map for storage
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
      'teamId': teamId,
      'employeeIds': employeeIds,
      'address': address,
      'phoneNumber': phoneNumber,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'archived': isArchived,
      'recurringGroupId': recurringGroupId,
      'reminderSentAt': reminderSentAt,
      'checklistItems': checklistItems.map((item) => item.toMap()).toList(),
      'routeOrder': routeOrder,
    };
  }
}

/// status constants for scheduled work lifecycle
class ScheduledWorkStatus {
  /// initial status when work is scheduled
  static const scheduled = 'scheduled';
  /// status when work is finished
  static const completed = 'completed';
  /// status when completed work has been invoiced
  static const invoiced = 'invoiced';
}
