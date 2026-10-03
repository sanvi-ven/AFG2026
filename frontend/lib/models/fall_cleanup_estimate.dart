import 'package:cloud_firestore/cloud_firestore.dart';

/// the three fall cleanup packages the owner can price and send. All three
/// are always shown on an estimate (with a price, or "Not offered" when the
/// owner left that plan blank for a given property) — only whichever one
/// ends up in [FallCleanupEstimate.selectedPlan] ever counts toward the total.
class FallCleanupPlan {
  FallCleanupPlan._();

  static const essential = 'essential';
  static const premium = 'premium';
  static const both = 'both';
  static const all = [essential, premium, both];

  static String displayLabel(String key) => switch (key) {
        essential => 'Essential',
        premium => 'Premium',
        both => 'Both (two visits)',
        _ => key,
      };
}

/// what happens to the leaves once the cleanup is done.
class FallCleanupDisposalChoice {
  FallCleanupDisposalChoice._();

  static const woodsOrCurb = 'woods_or_curb'; // no charge
  static const bagAndLeave = 'bag_and_leave'; // extra charge
  static const haulAway = 'haul_away'; // extra charge
  static const all = [woodsOrCurb, bagAndLeave, haulAway];

  static String displayLabel(String key) => switch (key) {
        woodsOrCurb => 'Blow to woods or curb',
        bagAndLeave => 'Bag and leave',
        haulAway => 'Full haul-away',
        _ => key,
      };
}

class FallCleanupStatus {
  FallCleanupStatus._();

  /// sent, no plan approved yet
  static const pending = 'pending';

  /// a plan has been approved — either the client tapped Approve on one of
  /// the three plan cards, or the owner recorded a phone/text approval
  static const signed = 'signed';
  static const changesRequested = 'changes_requested';
}

/// a fall cleanup estimate: always shows all three [FallCleanupPlan] options
/// with their prices, a leaf-disposal choice, optional additional work, and
/// the frozen fall-cleanup policy text. Separate from the general-purpose
/// [Estimate]/`estimates` collection — see CLAUDE.md for why.
class FallCleanupEstimate {
  const FallCleanupEstimate({
    required this.id,
    required this.estimateNumber,
    required this.clientId,
    this.essentialPrice,
    this.premiumPrice,
    this.bothPrice,
    this.selectedPlan,
    required this.disposalChoice,
    this.disposalFee = 0,
    this.whereLeavesCanGo = '',
    this.additionalWorkDescription = '',
    this.additionalWorkAmount,
    this.additionalWorkNeedsQuote = false,
    this.notes = '',
    required this.policyContent,
    required this.total,
    required this.status,
    this.changeRequestMessage,
    this.changeRequestedAt,
    this.approvedByOwner = false,
    this.ownerApprovalMethod,
    this.ownerApprovalNote,
    this.ownerApprovedAt,
    required this.createdAt,
    required this.updatedAt,
    this.convertedToInvoice = false,
    this.convertedInvoiceId,
    this.convertedAt,
    this.isScheduled = false,
    this.scheduledWorkId,
    this.isArchived = false,
  });

  final String id;
  final String estimateNumber;
  final String clientId;

  // All three plans are always shown; price is null when the owner hasn't
  // offered/priced that plan for this property. Only one ever counts toward
  // the total — whichever [selectedPlan] names.
  final double? essentialPrice;
  final double? premiumPrice;
  final double? bothPrice;
  final String? selectedPlan;

  final String disposalChoice;
  final double disposalFee;
  final String whereLeavesCanGo;

  final String additionalWorkDescription;
  final double? additionalWorkAmount;

  /// when true, [additionalWorkAmount] is ignored and the estimate/PDF show
  /// "Separate quote upon request" instead of a price
  final bool additionalWorkNeedsQuote;

  final String notes;

  /// frozen snapshot of legal_documents/fall_cleanup_policy, taken at
  /// creation — never re-reads the live template, so a later edit to the
  /// owner-editable wording doesn't silently reword an estimate already sent.
  final String policyContent;

  final double total;
  final String status;
  final String? changeRequestMessage;
  final DateTime? changeRequestedAt;

  /// true when the owner recorded the client's approval (phone/text) rather
  /// than the client tapping Approve themselves
  final bool approvedByOwner;
  final String? ownerApprovalMethod; // 'phone' | 'text'
  final String? ownerApprovalNote;
  final DateTime? ownerApprovedAt;

  final DateTime createdAt;
  final DateTime updatedAt;
  final bool convertedToInvoice;
  final String? convertedInvoiceId;
  final DateTime? convertedAt;
  final bool isScheduled;
  final String? scheduledWorkId;
  final bool isArchived;

  bool get isPending => status == FallCleanupStatus.pending;
  bool get isSigned => status == FallCleanupStatus.signed;
  bool get isChangesRequested => status == FallCleanupStatus.changesRequested;
  bool get isConvertible => isSigned && !convertedToInvoice;

  /// the price the owner set for [plan], or null if that plan isn't offered
  /// for this property
  double? priceFor(String plan) => switch (plan) {
        FallCleanupPlan.essential => essentialPrice,
        FallCleanupPlan.premium => premiumPrice,
        FallCleanupPlan.both => bothPrice,
        _ => null,
      };

  factory FallCleanupEstimate.fromMap(Map<String, dynamic> map) {
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

    return FallCleanupEstimate(
      id: (map['id'] as String? ?? '').trim(),
      estimateNumber: (map['estimateNumber'] as String? ?? '').trim(),
      clientId: (map['clientId'] as String? ?? '').trim(),
      essentialPrice: (map['essentialPrice'] as num?)?.toDouble(),
      premiumPrice: (map['premiumPrice'] as num?)?.toDouble(),
      bothPrice: (map['bothPrice'] as num?)?.toDouble(),
      selectedPlan: (map['selectedPlan'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['selectedPlan'] as String).trim(),
      disposalChoice: (map['disposalChoice'] as String? ??
              FallCleanupDisposalChoice.woodsOrCurb)
          .trim(),
      disposalFee: (map['disposalFee'] as num? ?? 0).toDouble(),
      whereLeavesCanGo: (map['whereLeavesCanGo'] as String? ?? '').trim(),
      additionalWorkDescription:
          (map['additionalWorkDescription'] as String? ?? '').trim(),
      additionalWorkAmount: (map['additionalWorkAmount'] as num?)?.toDouble(),
      additionalWorkNeedsQuote:
          map['additionalWorkNeedsQuote'] as bool? ?? false,
      notes: (map['notes'] as String? ?? '').trim(),
      policyContent: (map['policyContent'] as String? ?? ''),
      total: (map['total'] as num? ?? 0).toDouble(),
      status: (map['status'] as String? ?? FallCleanupStatus.pending).trim(),
      changeRequestMessage: (map['changeRequestMessage'] as String?)?.trim(),
      changeRequestedAt: readOptionalDate(map['changeRequestedAt']),
      approvedByOwner: map['approvedByOwner'] as bool? ?? false,
      ownerApprovalMethod: (map['ownerApprovalMethod'] as String?)?.trim(),
      ownerApprovalNote: (map['ownerApprovalNote'] as String?)?.trim(),
      ownerApprovedAt: readOptionalDate(map['ownerApprovedAt']),
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
      convertedToInvoice: map['convertedToInvoice'] as bool? ?? false,
      convertedInvoiceId: (map['convertedInvoiceId'] as String?)?.trim(),
      convertedAt: readOptionalDate(map['convertedAt']),
      isScheduled: map['isScheduled'] as bool? ?? false,
      scheduledWorkId: (map['scheduledWorkId'] as String?)?.trim(),
      isArchived: map['archived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'estimateNumber': estimateNumber,
      'clientId': clientId,
      'essentialPrice': essentialPrice,
      'premiumPrice': premiumPrice,
      'bothPrice': bothPrice,
      'selectedPlan': selectedPlan,
      'disposalChoice': disposalChoice,
      'disposalFee': disposalFee,
      'whereLeavesCanGo': whereLeavesCanGo,
      'additionalWorkDescription': additionalWorkDescription,
      'additionalWorkAmount': additionalWorkAmount,
      'additionalWorkNeedsQuote': additionalWorkNeedsQuote,
      'notes': notes,
      'policyContent': policyContent,
      'total': total,
      'status': status,
      'changeRequestMessage': changeRequestMessage,
      'changeRequestedAt': changeRequestedAt,
      'approvedByOwner': approvedByOwner,
      'ownerApprovalMethod': ownerApprovalMethod,
      'ownerApprovalNote': ownerApprovalNote,
      'ownerApprovedAt': ownerApprovedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'convertedToInvoice': convertedToInvoice,
      'convertedInvoiceId': convertedInvoiceId,
      'convertedAt': convertedAt,
      'isScheduled': isScheduled,
      'scheduledWorkId': scheduledWorkId,
      'archived': isArchived,
    };
  }
}
