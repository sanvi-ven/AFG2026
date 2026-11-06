import 'package:cloud_firestore/cloud_firestore.dart';

import 'fall_cleanup.dart';
import 'invoice.dart';

/// represents a service estimate quote with revision and conversion tracking
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
    this.isArchived = false,
    this.approvedByOwner = false,
    this.ownerApprovalMethod,
    this.ownerApprovalNote,
    this.ownerApprovedAt,
    this.notes = '',
    this.terms = '',
    this.depositPercent,
    this.type = EstimateType.standard,
    this.fallCleanup,
    this.secondVisitInvoiceId,
    this.discount,
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
  final bool isArchived;

  /// true when the owner approved on the client's behalf (e.g. phone/text confirmation)
  final bool approvedByOwner;

  /// 'phone' or 'text' — how the owner confirmed the client's approval
  final String? ownerApprovalMethod;
  final String? ownerApprovalNote;
  final DateTime? ownerApprovedAt;
  final String notes;
  final String terms;

  /// percentage (0-100) of the total due upfront to begin work; null means
  /// no deposit is required for this estimate
  final double? depositPercent;

  /// [EstimateType.standard] or [EstimateType.fallCleanup]
  final String type;

  /// package/disposal/extras prices and selection; set only when [type] is
  /// [EstimateType.fallCleanup]. [services] then holds the "Additional Work"
  /// rows, and [total] is derived from both (see [FallCleanupDetails.knownTotal]).
  final FallCleanupDetails? fallCleanup;

  /// fall cleanup "Both (Two Visits)" only: the visit-2 invoice. The visit-1
  /// invoice is [convertedInvoiceId], each billing 50% of the total.
  final String? secondVisitInvoiceId;

  /// optional flat or percent discount off [subtotal]. On a fall cleanup
  /// it applies to whatever the client picks, so a percent discount scales
  /// with their choice and a flat one is capped at it.
  final EstimateDiscount? discount;

  /// total before any discount: the line items, or for a fall cleanup the
  /// priced selected options plus additional work
  double get subtotal => isFallCleanup
      ? fallCleanup!.knownTotal(services)
      : services.fold<double>(
          0, (runningTotal, item) => runningTotal + item.price);

  /// dollar amount taken off by [discount]; 0 when there's none
  double get discountAmount => discount?.amountFor(subtotal) ?? 0;

  bool get isFallCleanup =>
      type == EstimateType.fallCleanup && fallCleanup != null;

  /// the line items to invoice or schedule: [services] for a standard
  /// estimate, or the selected fall cleanup options plus additional work.
  /// A discount is carried as a trailing negative line, so an invoice or job
  /// built from these items totals to exactly the discounted [total].
  List<InvoiceServiceItem> get billableServices {
    final items =
        isFallCleanup ? fallCleanup!.billableItems(services) : services;
    final amount = discountAmount;
    if (amount <= 0) return items;
    return [
      ...items,
      InvoiceServiceItem(name: discount!.label, price: -amount),
    ];
  }

  bool get isPending => status == InvoiceStatus.pending;
  bool get isApproved => status == InvoiceStatus.approved;
  bool get isDenied => status == InvoiceStatus.denied;
  bool get isChangesRequested => status == InvoiceStatus.changesRequested;
  bool get isConvertible => isApproved && !convertedToInvoice;

  /// create estimate from firestore map data
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

    final type = (map['type'] as String? ?? EstimateType.standard).trim();
    final discount = EstimateDiscount.fromMapOrNull(map['discount']);
    final fallCleanupMap = map['fallCleanup'];
    final fallCleanup = type == EstimateType.fallCleanup &&
            fallCleanupMap is Map
        ? FallCleanupDetails.fromMap(
            fallCleanupMap.map((key, value) => MapEntry(key.toString(), value)))
        : null;

    return Estimate(
      id: (map['id'] as String? ?? '').trim(),
      estimateNumber: (map['estimateNumber'] as String? ?? '').trim(),
      clientId: (map['clientId'] as String? ?? '').trim(),
      services: serviceRows,
      // a fall cleanup total is always derived, never trusted from the doc:
      // a client's approval writes only the selection (Firestore rules keep
      // them off `total` and the prices), so a stored total can be stale
      total: fallCleanup != null
          ? () {
              final known = fallCleanup.knownTotal(serviceRows);
              return known - (discount?.amountFor(known) ?? 0);
            }()
          : (map['total'] as num? ?? 0).toDouble(),
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
      isArchived: map['archived'] as bool? ?? false,
      approvedByOwner: map['approvedByOwner'] as bool? ?? false,
      ownerApprovalMethod: (map['ownerApprovalMethod'] as String?)?.trim(),
      ownerApprovalNote: (map['ownerApprovalNote'] as String?)?.trim(),
      ownerApprovedAt: readOptionalDate(map['ownerApprovedAt']),
      notes: (map['notes'] as String? ?? '').trim(),
      terms: (map['terms'] as String? ?? '').trim(),
      depositPercent: (map['depositPercent'] as num?)?.toDouble(),
      type: type,
      fallCleanup: fallCleanup,
      secondVisitInvoiceId: (map['secondVisitInvoiceId'] as String?)?.trim(),
      discount: discount,
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
      'archived': isArchived,
      'approvedByOwner': approvedByOwner,
      'ownerApprovalMethod': ownerApprovalMethod,
      'ownerApprovalNote': ownerApprovalNote,
      'ownerApprovedAt': ownerApprovedAt,
      'notes': notes,
      'terms': terms,
      'depositPercent': depositPercent,
      'type': type,
      'fallCleanup': fallCleanup?.toMap(),
      'secondVisitInvoiceId': secondVisitInvoiceId,
      'discount': discount?.toMap(),
    };
  }
}

/// a discount off an estimate's subtotal: either a flat dollar amount or a
/// percentage
class EstimateDiscount {
  const EstimateDiscount({required this.type, required this.value});

  static const flat = 'flat';
  static const percent = 'percent';

  /// [flat] or [percent]
  final String type;

  /// dollars for [flat], 0-100 for [percent]
  final double value;

  bool get isPercent => type == percent;

  /// line-item name shown on estimates, invoices, and PDFs
  String get label =>
      isPercent ? 'Discount (${_trimNumber(value)}%)' : 'Discount';

  /// dollars taken off [subtotal], rounded to the cent and never more than
  /// the subtotal itself
  double amountFor(double subtotal) {
    if (subtotal <= 0 || value <= 0) return 0;
    final raw = isPercent ? subtotal * value / 100 : value;
    final cents = (raw * 100).round();
    final capped =
        cents > (subtotal * 100).round() ? (subtotal * 100).round() : cents;
    return capped / 100;
  }

  /// "10% off" or "\$50.00 off", for when there's no total to show the
  /// dollar amount against yet (a fall cleanup the client hasn't picked)
  String get offText => isPercent
      ? '${_trimNumber(value)}% off'
      : '\$${value.toStringAsFixed(2)} off';

  static String _trimNumber(double n) => n == n.roundToDouble()
      ? n.toStringAsFixed(0)
      : n.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  static EstimateDiscount? fromMapOrNull(dynamic map) {
    if (map is! Map) return null;
    final value = (map['value'] as num?)?.toDouble() ?? 0;
    if (value <= 0) return null;
    return EstimateDiscount(
      type: map['type'] == percent ? percent : flat,
      value: value,
    );
  }

  Map<String, dynamic> toMap() => {'type': type, 'value': value};
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

  /// create version snapshot from firestore map
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

  /// convert version snapshot to firestore map
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
