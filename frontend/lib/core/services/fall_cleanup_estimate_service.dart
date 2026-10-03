import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/fall_cleanup_estimate.dart';
import '../../models/legal_document.dart';
import 'legal_document_service.dart';

/// manages fall cleanup estimate data in firestore — a separate collection
/// from the general-purpose `estimates` (see EstimateService), since the
/// data shape is a fixed plan menu rather than a dynamic line-item list.
class FallCleanupEstimateService {
  FallCleanupEstimateService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('fall_cleanup_estimates');
  static final DocumentReference<Map<String, dynamic>> _ownerSettingsDoc =
      _firestore.collection('owner_settings').doc('default');

  static String _formatEstimateNumber(int n) =>
      'FC-${n.toString().padLeft(4, '0')}';

  /// preview the next fall cleanup estimate number without consuming it
  static Future<String> peekNextFallCleanupNumber() async {
    final snapshot = await _ownerSettingsDoc.get();
    final current =
        (snapshot.data()?['next_fall_cleanup_number'] as num?)?.toInt() ?? 1;
    return _formatEstimateNumber(current);
  }

  /// atomically read-and-increment the next fall cleanup estimate number
  static Future<String> consumeNextFallCleanupNumber() {
    return _firestore.runTransaction<String>((transaction) async {
      final snapshot = await transaction.get(_ownerSettingsDoc);
      final current =
          (snapshot.data()?['next_fall_cleanup_number'] as num?)?.toInt() ??
              1;
      transaction.set(
        _ownerSettingsDoc,
        {'next_fall_cleanup_number': current + 1},
        SetOptions(merge: true),
      );
      return _formatEstimateNumber(current);
    });
  }

  /// listen to real-time fall cleanup estimate updates, filtered by role and clientId
  static Stream<List<FallCleanupEstimate>> watchEstimates(
      {required String role, String? clientId}) {
    Query<Map<String, dynamic>> query = _collection;
    if (role == 'client' && clientId != null && clientId.trim().isNotEmpty) {
      query = query.where('clientId', isEqualTo: clientId.trim());
    }

    return query.snapshots().map((snapshot) {
      final estimates = snapshot.docs
          .map((doc) {
            final data = doc.data();
            return FallCleanupEstimate.fromMap({...data, 'id': doc.id});
          })
          .where((e) => role == 'owner' || !e.isArchived)
          .toList();
      estimates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return estimates;
    });
  }

  static Future<LegalDocument> _requireFrozenPolicy() async {
    final template = await LegalDocumentService.fetchDocument(
        LegalDocumentIds.fallCleanupPolicy);
    final content = template?.content.trim() ?? '';
    if (content.isEmpty) {
      throw Exception(
          'Set up the fall cleanup policy first, in Owner Settings → Manage Legal Documents.');
    }
    return template!;
  }

  static double _computeTotal({
    required String? selectedPlan,
    required double? essentialPrice,
    required double? premiumPrice,
    required double? bothPrice,
    required double disposalFee,
    required double? additionalWorkAmount,
    required bool additionalWorkNeedsQuote,
  }) {
    if (selectedPlan == null) return 0;
    final planPrice = switch (selectedPlan) {
      FallCleanupPlan.essential => essentialPrice,
      FallCleanupPlan.premium => premiumPrice,
      FallCleanupPlan.both => bothPrice,
      _ => null,
    };
    final extra = additionalWorkNeedsQuote ? 0.0 : (additionalWorkAmount ?? 0);
    return (planPrice ?? 0) + disposalFee + extra;
  }

  /// create a new, pending fall cleanup estimate with no plan approved yet
  static Future<String> createEstimate({
    required String estimateNumber,
    required String clientId,
    double? essentialPrice,
    double? premiumPrice,
    double? bothPrice,
    required String disposalChoice,
    double disposalFee = 0,
    String whereLeavesCanGo = '',
    String additionalWorkDescription = '',
    double? additionalWorkAmount,
    bool additionalWorkNeedsQuote = false,
    String notes = '',
  }) async {
    final policy = await _requireFrozenPolicy();
    final now = DateTime.now();
    final doc = _collection.doc();

    final estimate = FallCleanupEstimate(
      id: doc.id,
      estimateNumber: estimateNumber.trim(),
      clientId: clientId.trim(),
      essentialPrice: essentialPrice,
      premiumPrice: premiumPrice,
      bothPrice: bothPrice,
      disposalChoice: disposalChoice,
      disposalFee: disposalFee,
      whereLeavesCanGo: whereLeavesCanGo.trim(),
      additionalWorkDescription: additionalWorkDescription.trim(),
      additionalWorkAmount: additionalWorkNeedsQuote ? null : additionalWorkAmount,
      additionalWorkNeedsQuote: additionalWorkNeedsQuote,
      notes: notes.trim(),
      policyContent: policy.content,
      total: 0,
      status: FallCleanupStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    await doc.set(estimate.toMap());
    return doc.id;
  }

  /// owner action: create a fall cleanup estimate that's already approved —
  /// for when the client already told the owner (by phone/text) which plan
  /// they want, mirroring EstimateService.createApprovedEstimate.
  static Future<String> createApprovedEstimate({
    required String estimateNumber,
    required String clientId,
    double? essentialPrice,
    double? premiumPrice,
    double? bothPrice,
    required String selectedPlan,
    required String disposalChoice,
    double disposalFee = 0,
    String whereLeavesCanGo = '',
    String additionalWorkDescription = '',
    double? additionalWorkAmount,
    bool additionalWorkNeedsQuote = false,
    String notes = '',
    required String approvalMethod,
    String approvalNote = '',
  }) async {
    final policy = await _requireFrozenPolicy();
    final now = DateTime.now();
    final doc = _collection.doc();
    final total = _computeTotal(
      selectedPlan: selectedPlan,
      essentialPrice: essentialPrice,
      premiumPrice: premiumPrice,
      bothPrice: bothPrice,
      disposalFee: disposalFee,
      additionalWorkAmount: additionalWorkAmount,
      additionalWorkNeedsQuote: additionalWorkNeedsQuote,
    );

    final estimate = FallCleanupEstimate(
      id: doc.id,
      estimateNumber: estimateNumber.trim(),
      clientId: clientId.trim(),
      essentialPrice: essentialPrice,
      premiumPrice: premiumPrice,
      bothPrice: bothPrice,
      selectedPlan: selectedPlan,
      disposalChoice: disposalChoice,
      disposalFee: disposalFee,
      whereLeavesCanGo: whereLeavesCanGo.trim(),
      additionalWorkDescription: additionalWorkDescription.trim(),
      additionalWorkAmount: additionalWorkNeedsQuote ? null : additionalWorkAmount,
      additionalWorkNeedsQuote: additionalWorkNeedsQuote,
      notes: notes.trim(),
      policyContent: policy.content,
      total: total,
      status: FallCleanupStatus.signed,
      approvedByOwner: true,
      ownerApprovalMethod: approvalMethod,
      ownerApprovalNote: approvalNote.trim(),
      ownerApprovedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    await doc.set(estimate.toMap());
    return doc.id;
  }

  /// owner action: edit a still-pending/changes-requested estimate's
  /// priceable fields in place. If status was changes_requested, resets it
  /// to pending and clears the change-request message — no revision/diff
  /// history, unlike EstimateService.reviseAndResendEstimate.
  static Future<void> updateEstimate({
    required String estimateId,
    double? essentialPrice,
    double? premiumPrice,
    double? bothPrice,
    required String disposalChoice,
    double disposalFee = 0,
    String whereLeavesCanGo = '',
    String additionalWorkDescription = '',
    double? additionalWorkAmount,
    bool additionalWorkNeedsQuote = false,
    String notes = '',
  }) async {
    final snapshot = await _collection.doc(estimateId).get();
    final data = snapshot.data();
    final currentStatus = (data?['status'] as String?) ?? FallCleanupStatus.pending;
    final selectedPlan = (data?['selectedPlan'] as String?)?.trim().isEmpty ?? true
        ? null
        : (data!['selectedPlan'] as String).trim();

    final payload = <String, dynamic>{
      'essentialPrice': essentialPrice,
      'premiumPrice': premiumPrice,
      'bothPrice': bothPrice,
      'disposalChoice': disposalChoice,
      'disposalFee': disposalFee,
      'whereLeavesCanGo': whereLeavesCanGo.trim(),
      'additionalWorkDescription': additionalWorkDescription.trim(),
      'additionalWorkAmount': additionalWorkNeedsQuote ? null : additionalWorkAmount,
      'additionalWorkNeedsQuote': additionalWorkNeedsQuote,
      'notes': notes.trim(),
      'total': _computeTotal(
        selectedPlan: selectedPlan,
        essentialPrice: essentialPrice,
        premiumPrice: premiumPrice,
        bothPrice: bothPrice,
        disposalFee: disposalFee,
        additionalWorkAmount: additionalWorkAmount,
        additionalWorkNeedsQuote: additionalWorkNeedsQuote,
      ),
      'updatedAt': DateTime.now(),
    };

    if (currentStatus == FallCleanupStatus.changesRequested) {
      payload['status'] = FallCleanupStatus.pending;
      payload['changeRequestMessage'] = null;
      payload['changeRequestedAt'] = null;
    }

    await _collection.doc(estimateId).set(payload, SetOptions(merge: true));
  }

  /// client action: request changes with a message
  static Future<void> requestChanges({
    required String estimateId,
    required String message,
  }) async {
    await _collection.doc(estimateId).set(
      {
        'status': FallCleanupStatus.changesRequested,
        'changeRequestMessage': message.trim(),
        'changeRequestedAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// client action: approve one of the three offered plans. Re-reads first
  /// and refuses if a plan has already been chosen — defense in depth
  /// alongside the Firestore rule's write-once `selectedPlan` guard.
  static Future<void> approvePlan({
    required String estimateId,
    required String plan,
  }) async {
    final snapshot = await _collection.doc(estimateId).get();
    final data = snapshot.data();
    if (data == null) {
      throw Exception('This estimate could not be found.');
    }
    final existingPlan = (data['selectedPlan'] as String?)?.trim() ?? '';
    if (existingPlan.isNotEmpty) {
      throw Exception('A plan has already been approved on this estimate.');
    }

    final total = _computeTotal(
      selectedPlan: plan,
      essentialPrice: (data['essentialPrice'] as num?)?.toDouble(),
      premiumPrice: (data['premiumPrice'] as num?)?.toDouble(),
      bothPrice: (data['bothPrice'] as num?)?.toDouble(),
      disposalFee: (data['disposalFee'] as num? ?? 0).toDouble(),
      additionalWorkAmount: (data['additionalWorkAmount'] as num?)?.toDouble(),
      additionalWorkNeedsQuote: data['additionalWorkNeedsQuote'] as bool? ?? false,
    );

    await _collection.doc(estimateId).set(
      {
        'selectedPlan': plan,
        'status': FallCleanupStatus.signed,
        'total': total,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// owner action: approve a pending estimate on the client's behalf after
  /// getting confirmation by phone or text outside the app, naming which
  /// plan the client chose.
  static Future<void> approveByOwner({
    required String estimateId,
    required String plan,
    required String method,
    String note = '',
  }) async {
    final snapshot = await _collection.doc(estimateId).get();
    final data = snapshot.data() ?? const <String, dynamic>{};

    final total = _computeTotal(
      selectedPlan: plan,
      essentialPrice: (data['essentialPrice'] as num?)?.toDouble(),
      premiumPrice: (data['premiumPrice'] as num?)?.toDouble(),
      bothPrice: (data['bothPrice'] as num?)?.toDouble(),
      disposalFee: (data['disposalFee'] as num? ?? 0).toDouble(),
      additionalWorkAmount: (data['additionalWorkAmount'] as num?)?.toDouble(),
      additionalWorkNeedsQuote: data['additionalWorkNeedsQuote'] as bool? ?? false,
    );

    await _collection.doc(estimateId).set(
      {
        'selectedPlan': plan,
        'status': FallCleanupStatus.signed,
        'total': total,
        'approvedByOwner': true,
        'ownerApprovalMethod': method,
        'ownerApprovalNote': note.trim(),
        'ownerApprovedAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> archiveEstimate(String estimateId) async {
    await _collection.doc(estimateId).set(
      {'archived': true, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  /// owner action: permanently remove an archived estimate, refusing if it
  /// still has an invoice or scheduled job on file — same guard shape as
  /// EstimateService.deleteEstimatePermanently.
  static Future<void> deleteEstimatePermanently(String estimateId) async {
    final normalizedId = estimateId.trim();

    final guards = {
      'invoices': const MapEntry('sourceEstimateId', 'an invoice'),
      'scheduled_work': const MapEntry('estimateId', 'a scheduled job'),
    };
    for (final entry in guards.entries) {
      final match = await _firestore
          .collection(entry.key)
          .where(entry.value.key, isEqualTo: normalizedId)
          .limit(1)
          .get();
      if (match.docs.isNotEmpty) {
        throw Exception(
          "This estimate still has ${entry.value.value} on file and can't be permanently deleted.",
        );
      }
    }

    await _collection.doc(normalizedId).delete();
  }

  static Future<void> markConverted({
    required String estimateId,
    required String invoiceId,
  }) async {
    await _collection.doc(estimateId).set(
      {
        'convertedToInvoice': true,
        'convertedInvoiceId': invoiceId,
        'convertedAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> markScheduled({
    required String estimateId,
    required String scheduledWorkId,
  }) async {
    await _collection.doc(estimateId).set(
      {
        'isScheduled': true,
        'scheduledWorkId': scheduledWorkId,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<FallCleanupEstimate?> fetchById(String estimateId) async {
    final normalizedId = estimateId.trim();
    if (normalizedId.isEmpty) return null;
    final snapshot = await _collection.doc(normalizedId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return FallCleanupEstimate.fromMap({...data, 'id': snapshot.id});
  }
}
