import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/contract_amendment.dart';
import '../../models/employment_contract.dart';

/// manages employment contract amendments in firestore. An amendment only
/// takes effect on the parent employment_contracts doc once every required
/// party has initialed — see [applyAmendmentToContract]'s doc comment for
/// why that final step is deliberately owner-only, not automatic.
class ContractAmendmentService {
  ContractAmendmentService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('contract_amendments');
  static final CollectionReference<Map<String, dynamic>> _contractsCollection =
      _firestore.collection('employment_contracts');

  /// owner-facing roster view — every amendment across every employee, to be
  /// merged client-side against the employee/contract streams, same
  /// "one stream, split client-side" approach used elsewhere in this app.
  static Stream<List<ContractAmendment>> watchAllAmendments() {
    return _collection.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => ContractAmendment.fromMap({...doc.data(), 'id': doc.id}))
        .toList());
  }

  static Stream<List<ContractAmendment>> watchAmendmentsForEmployee(String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId.trim())
        .snapshots()
        .map((snapshot) {
      final amendments = snapshot.docs
          .map((doc) => ContractAmendment.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      amendments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return amendments;
    });
  }

  /// the employee's own view only ever needs the single most recent
  /// not-yet-fully-initialed amendment, if any, to show a re-initial banner.
  static Stream<ContractAmendment?> watchPendingAmendmentForEmployee(String employeeId) {
    return watchAmendmentsForEmployee(employeeId).map((amendments) {
      for (final amendment in amendments) {
        if (!amendment.isFullyInitialed) return amendment;
      }
      return null;
    });
  }

  /// owner action: draft an amendment against an already-issued contract.
  /// changedSections are owner-identified manually, not auto-diffed.
  static Future<String> draftAmendment({
    required EmploymentContract contract,
    required List<AmendmentChangedSection> changedSections,
    required String fullContentSnapshot,
    required bool isMinorAtSigning,
    required bool guardianRequired,
    String guardianName = '',
    String guardianEmail = '',
    String guardianPhone = '',
    required String createdBy,
  }) async {
    final doc = _collection.doc();
    final now = DateTime.now();
    final amendment = ContractAmendment(
      id: doc.id,
      contractId: contract.id,
      employeeId: contract.employeeId,
      version: contract.contractVersion + 1,
      changedSections: changedSections,
      fullContentSnapshot: fullContentSnapshot,
      isMinorAtSigning: isMinorAtSigning,
      guardianRequired: guardianRequired,
      guardianName: guardianName,
      guardianEmail: guardianEmail,
      guardianPhone: guardianPhone,
      status: AmendmentStatus.pendingEmployeeInitial,
      createdAt: now,
      createdBy: createdBy,
    );
    await doc.set(amendment.toMap());
    return doc.id;
  }

  /// employee action: initial an amendment. Recomputes status from both
  /// initials, not just "is a guardian required" — same reasoning as
  /// ContractService.submitEmployeeSignature: the guardian can initial
  /// before the employee does, and this must check whether guardianInitials
  /// is already there rather than always assuming it still needs to happen.
  static Future<void> submitEmployeeInitial({
    required String amendmentId,
    required ContractSignature initials,
  }) async {
    final doc = _collection.doc(amendmentId.trim());
    final snapshot = await doc.get();
    final data = snapshot.data();
    if (data == null) {
      throw Exception('Amendment not found.');
    }
    final amendment = ContractAmendment.fromMap({...data, 'id': snapshot.id});
    if (amendment.employeeInitials != null) {
      throw Exception('This amendment has already been initialed.');
    }

    final stillNeedsGuardian = amendment.guardianRequired && amendment.guardianInitials == null;
    final newStatus =
        stillNeedsGuardian ? AmendmentStatus.pendingGuardianInitial : AmendmentStatus.fullyInitialed;
    await doc.set(
      {
        'employeeInitials': initials.toMap(),
        'status': newStatus,
      },
      SetOptions(merge: true),
    );
  }

  /// owner action, and only the owner — this writes `content`/
  /// `contractVersion` on employment_contracts, which firestore.rules
  /// restricts to the owner specifically so an employee can never rewrite
  /// their own contract's effective text. Once every required party has
  /// initialed (amendment.isFullyInitialed), the owner reviews and applies
  /// it here; prior amendment docs stay on file as the historical record of
  /// exactly what changed and who initialed it when.
  static Future<void> applyAmendmentToContract(ContractAmendment amendment) async {
    if (!amendment.isFullyInitialed) {
      throw Exception('This amendment still needs an initial before it can be applied.');
    }
    await _contractsCollection.doc(amendment.employeeId).set(
      {
        'content': amendment.fullContentSnapshot,
        'contractVersion': amendment.version,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }
}
