import 'package:cloud_firestore/cloud_firestore.dart';

/// status of one employee's current employment contract
class ContractStatus {
  static const pendingEmployeeSignature = 'pending_employee_signature';
  static const pendingGuardianSignature = 'pending_guardian_signature';
  static const fullySigned = 'fully_signed';
  static const uploadedSigned = 'uploaded_signed';
}

/// how a signature/initial was captured
class ContractSignatureMethod {
  static const typed = 'typed';
  static const drawn = 'drawn';
}

/// one signature or initial — either the employee's or the guardian's,
/// reused identically for both an original signature and an amendment initial
class ContractSignature {
  const ContractSignature({
    required this.method,
    this.typedName = '',
    this.drawingBase64 = '',
    required this.consentText,
    required this.signedAt,
  });

  final String method;
  final String typedName;
  final String drawingBase64;

  /// the exact consent checkbox wording the signer agreed to, frozen at
  /// signing time so it stays accurate even if the checkbox copy changes later
  final String consentText;
  final DateTime signedAt;

  factory ContractSignature.fromMap(Map<String, dynamic> map) {
    final rawSignedAt = map['signedAt'];
    return ContractSignature(
      method: (map['method'] as String? ?? '').trim(),
      typedName: (map['typedName'] as String? ?? '').trim(),
      drawingBase64: (map['drawingBase64'] as String? ?? '').trim(),
      consentText: (map['consentText'] as String? ?? '').trim(),
      signedAt: rawSignedAt is Timestamp
          ? rawSignedAt.toDate()
          : (rawSignedAt is String
              ? DateTime.tryParse(rawSignedAt) ?? DateTime.now()
              : DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'method': method,
      'typedName': typedName,
      'drawingBase64': drawingBase64,
      'consentText': consentText,
      'signedAt': signedAt,
    };
  }
}

/// an owner-uploaded scan/photo of an already-signed paper contract — the
/// terminal state for staff who signed before this feature existed
class UploadedContractFile {
  const UploadedContractFile({
    required this.url,
    required this.uploadedBy,
    required this.uploadedAt,
  });

  final String url;
  final String uploadedBy;
  final DateTime uploadedAt;

  factory UploadedContractFile.fromMap(Map<String, dynamic> map) {
    final rawUploadedAt = map['uploadedAt'];
    return UploadedContractFile(
      url: (map['url'] as String? ?? '').trim(),
      uploadedBy: (map['uploadedBy'] as String? ?? '').trim(),
      uploadedAt: rawUploadedAt is Timestamp
          ? rawUploadedAt.toDate()
          : (rawUploadedAt is String
              ? DateTime.tryParse(rawUploadedAt) ?? DateTime.now()
              : DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() {
    return {'url': url, 'uploadedBy': uploadedBy, 'uploadedAt': uploadedAt};
  }
}

/// one employee's current employment contract. Doc id == employeeId (one
/// live contract record per employee, like job_completion_forms keying by
/// workId) — an amendment updates [content]/[contractVersion] on this same
/// doc once fully initialed, rather than creating a new contract doc; the
/// historical record of what changed lives in contract_amendments instead.
class EmploymentContract {
  const EmploymentContract({
    required this.id,
    required this.employeeId,
    required this.content,
    required this.contractVersion,
    required this.isMinorAtSigning,
    required this.guardianRequired,
    this.guardianName = '',
    this.guardianEmail = '',
    this.guardianPhone = '',
    required this.status,
    this.employeeSignature,
    this.guardianSignature,
    this.guardianSignToken,
    this.guardianSignTokenExpiresAt,
    this.guardianSignTokenSentAt,
    this.guardianReminderCount = 0,
    this.uploadedFile,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
  });

  final String id;
  final String employeeId;

  /// frozen snapshot of the contract text — not a live reference into
  /// legal_documents, since a contract must not reword itself after signing
  final String content;
  final int contractVersion;

  /// snapshotted at issue time (and re-snapshotted per amendment) — doesn't
  /// move just because the employee's profile is edited later
  final bool isMinorAtSigning;
  final bool guardianRequired;
  final String guardianName;
  final String guardianEmail;
  final String guardianPhone;

  final String status;
  final ContractSignature? employeeSignature;
  final ContractSignature? guardianSignature;

  final String? guardianSignToken;
  final DateTime? guardianSignTokenExpiresAt;
  final DateTime? guardianSignTokenSentAt;
  final int guardianReminderCount;

  final UploadedContractFile? uploadedFile;

  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;

  bool get isFullySigned =>
      status == ContractStatus.fullySigned ||
      status == ContractStatus.uploadedSigned;
  bool get awaitingGuardianSignature =>
      status == ContractStatus.pendingGuardianSignature;

  static DateTime? _readOptionalDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  static DateTime _readDate(dynamic value) =>
      _readOptionalDate(value) ?? DateTime.now();

  factory EmploymentContract.fromMap(Map<String, dynamic> map) {
    final employeeSignatureMap = map['employeeSignature'];
    final guardianSignatureMap = map['guardianSignature'];
    final uploadedFileMap = map['uploadedFile'];

    return EmploymentContract(
      id: (map['id'] as String? ?? '').trim(),
      employeeId: (map['employeeId'] as String? ?? '').trim(),
      content: map['content'] as String? ?? '',
      contractVersion: (map['contractVersion'] as num? ?? 1).toInt(),
      isMinorAtSigning: map['isMinorAtSigning'] as bool? ?? false,
      guardianRequired: map['guardianRequired'] as bool? ?? false,
      guardianName: (map['guardianName'] as String? ?? '').trim(),
      guardianEmail: (map['guardianEmail'] as String? ?? '').trim(),
      guardianPhone: (map['guardianPhone'] as String? ?? '').trim(),
      status:
          (map['status'] as String? ?? ContractStatus.pendingEmployeeSignature)
              .trim(),
      employeeSignature: employeeSignatureMap is Map<String, dynamic>
          ? ContractSignature.fromMap(employeeSignatureMap)
          : null,
      guardianSignature: guardianSignatureMap is Map<String, dynamic>
          ? ContractSignature.fromMap(guardianSignatureMap)
          : null,
      guardianSignToken: (map['guardianSignToken'] as String?)?.trim(),
      guardianSignTokenExpiresAt:
          _readOptionalDate(map['guardianSignTokenExpiresAt']),
      guardianSignTokenSentAt:
          _readOptionalDate(map['guardianSignTokenSentAt']),
      guardianReminderCount: (map['guardianReminderCount'] as num? ?? 0).toInt(),
      uploadedFile: uploadedFileMap is Map<String, dynamic>
          ? UploadedContractFile.fromMap(uploadedFileMap)
          : null,
      createdAt: _readDate(map['createdAt']),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'content': content,
      'contractVersion': contractVersion,
      'isMinorAtSigning': isMinorAtSigning,
      'guardianRequired': guardianRequired,
      'guardianName': guardianName,
      'guardianEmail': guardianEmail,
      'guardianPhone': guardianPhone,
      'status': status,
      'employeeSignature': employeeSignature?.toMap(),
      'guardianSignature': guardianSignature?.toMap(),
      'guardianSignToken': guardianSignToken,
      'guardianSignTokenExpiresAt': guardianSignTokenExpiresAt,
      'guardianSignTokenSentAt': guardianSignTokenSentAt,
      'guardianReminderCount': guardianReminderCount,
      'uploadedFile': uploadedFile?.toMap(),
      'createdAt': createdAt,
      'createdBy': createdBy,
      'updatedAt': updatedAt,
    };
  }
}
