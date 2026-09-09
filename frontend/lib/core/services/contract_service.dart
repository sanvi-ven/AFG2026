import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/employee_profile.dart';
import '../../models/employment_contract.dart';
import '../../models/legal_document.dart';
import 'legal_document_service.dart';

/// manages employment contract data in firestore. Doc id == employeeId (one
/// live contract record per employee, like job_completion_forms keying by
/// workId) — an amendment updates content/contractVersion on this same doc
/// once fully initialed rather than creating a new one.
class ContractService {
  ContractService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('employment_contracts');

  static Stream<EmploymentContract?> watchContractForEmployee(String employeeId) {
    final normalizedId = employeeId.trim();
    return _collection.doc(normalizedId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return EmploymentContract.fromMap({...data, 'id': snapshot.id});
    });
  }

  /// owner-facing roster view — every employee's contract in one stream, to
  /// be merged client-side against EmployeeProfileService.watchAllProfiles(),
  /// same "one stream, split client-side" approach the archiving feature uses.
  static Stream<List<EmploymentContract>> watchAllContracts() {
    return _collection.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => EmploymentContract.fromMap({...doc.data(), 'id': doc.id}))
        .toList());
  }

  static Future<EmploymentContract?> fetchContractForEmployee(String employeeId) async {
    final normalizedId = employeeId.trim();
    if (normalizedId.isEmpty) return null;
    final snapshot = await _collection.doc(normalizedId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return EmploymentContract.fromMap({...data, 'id': snapshot.id});
  }

  /// owner action: issue a new contract for an employee, snapshotting the
  /// current employment-contract template and the employee's current
  /// DOB/guardian info. Throws if a contract already exists for them — an
  /// existing contract is changed via an amendment, not by re-issuing.
  ///
  /// [isMinorOverride] lets the caller supply an explicit adult/minor
  /// determination instead of trusting [EmployeeProfile.isMinor] — used when
  /// there's no dateOfBirth on file at all, since isMinor silently defaults
  /// to "adult" in that case and this is the one place that gap is closed:
  /// the owner is prompted to pick explicitly rather than it happening
  /// silently (see ContractsTab._issueContract).
  static Future<void> issueContract({
    required EmployeeProfile employee,
    required String issuedBy,
    bool? isMinorOverride,
  }) async {
    final normalizedId = employee.employeeId.trim();
    final doc = _collection.doc(normalizedId);
    final existing = await doc.get();
    if (existing.exists) {
      throw Exception('This employee already has a contract on file.');
    }

    final template = await LegalDocumentService.fetchDocument(
        LegalDocumentIds.employmentContractTemplate);
    final content = template?.content.trim() ?? '';
    if (content.isEmpty) {
      throw Exception(
          'Set up the employment contract template first, in Owner Settings → Manage Legal Documents.');
    }

    final isMinor = isMinorOverride ?? employee.isMinor;
    final now = DateTime.now();
    final contract = EmploymentContract(
      id: normalizedId,
      employeeId: normalizedId,
      content: content,
      contractVersion: 1,
      isMinorAtSigning: isMinor,
      guardianRequired: isMinor,
      guardianName: employee.guardianName,
      guardianEmail: employee.guardianEmail,
      guardianPhone: employee.guardianPhone,
      status: ContractStatus.pendingEmployeeSignature,
      createdAt: now,
      createdBy: issuedBy,
      updatedAt: now,
    );
    await doc.set(contract.toMap());
  }

  /// employee action: submit their own signature. Recomputes status from
  /// both signatures, not just "is a guardian required" — the guardian can
  /// sign before the employee does (there's nothing stopping them opening
  /// the emailed link first), so this must check whether guardianSignature
  /// is already there rather than always assuming it still needs to happen.
  /// Getting this wrong previously meant an employee signing after their
  /// already-signed guardian reset status back to "pending guardian
  /// signature" forever, since nothing re-checked it from that point on.
  static Future<void> submitEmployeeSignature({
    required String employeeId,
    required ContractSignature signature,
  }) async {
    final normalizedId = employeeId.trim();
    final doc = _collection.doc(normalizedId);
    final snapshot = await doc.get();
    final data = snapshot.data();
    if (data == null) {
      throw Exception('No contract found for this employee.');
    }
    final contract = EmploymentContract.fromMap({...data, 'id': snapshot.id});
    if (contract.employeeSignature != null) {
      throw Exception('This contract has already been signed.');
    }

    final stillNeedsGuardian = contract.guardianRequired && contract.guardianSignature == null;
    final newStatus =
        stillNeedsGuardian ? ContractStatus.pendingGuardianSignature : ContractStatus.fullySigned;
    await doc.set(
      {
        'employeeSignature': signature.toMap(),
        'status': newStatus,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// owner action: record an already-signed paper contract as the terminal
  /// state for an employee, as an alternative to the in-app e-sign flow —
  /// mainly for staff who signed before this feature existed. Creates a
  /// minimal contract doc if none exists yet.
  static Future<void> recordUploadedContract({
    required String employeeId,
    required String url,
    required String uploadedBy,
  }) async {
    final normalizedId = employeeId.trim();
    final doc = _collection.doc(normalizedId);
    final now = DateTime.now();
    final uploaded =
        UploadedContractFile(url: url, uploadedBy: uploadedBy, uploadedAt: now);

    final existing = await doc.get();
    if (existing.exists) {
      await doc.set(
        {
          'uploadedFile': uploaded.toMap(),
          'status': ContractStatus.uploadedSigned,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
      return;
    }

    final contract = EmploymentContract(
      id: normalizedId,
      employeeId: normalizedId,
      content: '',
      contractVersion: 1,
      isMinorAtSigning: false,
      guardianRequired: false,
      status: ContractStatus.uploadedSigned,
      uploadedFile: uploaded,
      createdAt: now,
      createdBy: uploadedBy,
      updatedAt: now,
    );
    await doc.set(contract.toMap());
  }

  /// owner action: permanently delete an employee's contract (and any
  /// amendments on it), so a fresh one can be issued or uploaded from
  /// scratch. Unlike the app's other "permanently delete" actions
  /// (ClientProfileService.deleteClientPermanently etc.), this doesn't
  /// refuse based on dependent records — a contract has no downstream
  /// financial/job data hanging off it the way an estimate or job does.
  static Future<void> deleteContract(String employeeId) async {
    final normalizedId = employeeId.trim();
    final amendments = await _firestore
        .collection('contract_amendments')
        .where('employeeId', isEqualTo: normalizedId)
        .get();
    if (amendments.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in amendments.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _collection.doc(normalizedId).delete();
  }

  /// stamp that a signature-pending SMS reminder was just sent, so
  /// ReminderCheckService doesn't re-text the employee on every dashboard scan
  static Future<void> markEmployeeSmsReminderSent(String employeeId) async {
    await _collection.doc(employeeId.trim()).set(
      {'employeeSmsReminderSentAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }
}
