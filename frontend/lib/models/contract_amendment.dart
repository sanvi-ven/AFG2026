import 'package:cloud_firestore/cloud_firestore.dart';

import 'employment_contract.dart';

class AmendmentStatus {
  static const pendingEmployeeInitial = 'pending_employee_initial';
  static const pendingGuardianInitial = 'pending_guardian_initial';
  static const fullyInitialed = 'fully_initialed';
}

/// one section the owner identified as changed by this amendment —
/// owner-marked manually, not auto-diffed against the previous text
class AmendmentChangedSection {
  const AmendmentChangedSection({
    required this.sectionHeading,
    required this.previousText,
    required this.newText,
  });

  final String sectionHeading;
  final String previousText;
  final String newText;

  factory AmendmentChangedSection.fromMap(Map<String, dynamic> map) {
    return AmendmentChangedSection(
      sectionHeading: (map['sectionHeading'] as String? ?? '').trim(),
      previousText: map['previousText'] as String? ?? '',
      newText: map['newText'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sectionHeading': sectionHeading,
      'previousText': previousText,
      'newText': newText,
    };
  }
}

/// a proposed change to an already-signed employment contract, requiring the
/// employee (and guardian, if applicable) to initial before it takes effect.
/// Kept as its own doc per amendment (rather than an array on the contract
/// doc) so firestore.rules can restrict a non-owner's write to exactly the
/// initials fields via onlyChanged, the same way every other per-event
/// collection in this app (time_entries, notifications) does.
class ContractAmendment {
  const ContractAmendment({
    required this.id,
    required this.contractId,
    required this.employeeId,
    required this.version,
    required this.changedSections,
    required this.fullContentSnapshot,
    required this.isMinorAtSigning,
    required this.guardianRequired,
    this.guardianName = '',
    this.guardianEmail = '',
    this.guardianPhone = '',
    required this.status,
    this.employeeInitials,
    this.guardianInitials,
    this.guardianInitialToken,
    this.guardianInitialTokenExpiresAt,
    this.guardianInitialTokenSentAt,
    this.guardianReminderCount = 0,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String contractId;
  final String employeeId;

  /// the contract version this amendment produces once fully initialed
  final int version;
  final List<AmendmentChangedSection> changedSections;
  final String fullContentSnapshot;

  /// re-snapshotted at amendment time, not copied from the original contract
  /// — an employee who was a minor at hire may have turned 18 since
  final bool isMinorAtSigning;
  final bool guardianRequired;
  final String guardianName;
  final String guardianEmail;
  final String guardianPhone;

  final String status;
  final ContractSignature? employeeInitials;
  final ContractSignature? guardianInitials;

  final String? guardianInitialToken;
  final DateTime? guardianInitialTokenExpiresAt;
  final DateTime? guardianInitialTokenSentAt;
  final int guardianReminderCount;

  final DateTime createdAt;
  final String createdBy;

  bool get isFullyInitialed => status == AmendmentStatus.fullyInitialed;

  static DateTime? _readOptionalDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  static DateTime _readDate(dynamic value) =>
      _readOptionalDate(value) ?? DateTime.now();

  factory ContractAmendment.fromMap(Map<String, dynamic> map) {
    final employeeInitialsMap = map['employeeInitials'];
    final guardianInitialsMap = map['guardianInitials'];
    final sections = (map['changedSections'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AmendmentChangedSection.fromMap)
        .toList();

    return ContractAmendment(
      id: (map['id'] as String? ?? '').trim(),
      contractId: (map['contractId'] as String? ?? '').trim(),
      employeeId: (map['employeeId'] as String? ?? '').trim(),
      version: (map['version'] as num? ?? 1).toInt(),
      changedSections: sections,
      fullContentSnapshot: map['fullContentSnapshot'] as String? ?? '',
      isMinorAtSigning: map['isMinorAtSigning'] as bool? ?? false,
      guardianRequired: map['guardianRequired'] as bool? ?? false,
      guardianName: (map['guardianName'] as String? ?? '').trim(),
      guardianEmail: (map['guardianEmail'] as String? ?? '').trim(),
      guardianPhone: (map['guardianPhone'] as String? ?? '').trim(),
      status: (map['status'] as String? ?? AmendmentStatus.pendingEmployeeInitial)
          .trim(),
      employeeInitials: employeeInitialsMap is Map<String, dynamic>
          ? ContractSignature.fromMap(employeeInitialsMap)
          : null,
      guardianInitials: guardianInitialsMap is Map<String, dynamic>
          ? ContractSignature.fromMap(guardianInitialsMap)
          : null,
      guardianInitialToken: (map['guardianInitialToken'] as String?)?.trim(),
      guardianInitialTokenExpiresAt:
          _readOptionalDate(map['guardianInitialTokenExpiresAt']),
      guardianInitialTokenSentAt:
          _readOptionalDate(map['guardianInitialTokenSentAt']),
      guardianReminderCount: (map['guardianReminderCount'] as num? ?? 0).toInt(),
      createdAt: _readDate(map['createdAt']),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contractId': contractId,
      'employeeId': employeeId,
      'version': version,
      'changedSections': changedSections.map((s) => s.toMap()).toList(),
      'fullContentSnapshot': fullContentSnapshot,
      'isMinorAtSigning': isMinorAtSigning,
      'guardianRequired': guardianRequired,
      'guardianName': guardianName,
      'guardianEmail': guardianEmail,
      'guardianPhone': guardianPhone,
      'status': status,
      'employeeInitials': employeeInitials?.toMap(),
      'guardianInitials': guardianInitials?.toMap(),
      'guardianInitialToken': guardianInitialToken,
      'guardianInitialTokenExpiresAt': guardianInitialTokenExpiresAt,
      'guardianInitialTokenSentAt': guardianInitialTokenSentAt,
      'guardianReminderCount': guardianReminderCount,
      'createdAt': createdAt,
      'createdBy': createdBy,
    };
  }
}
