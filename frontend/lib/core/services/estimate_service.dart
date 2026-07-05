/// made with help of chatgpt 4.0, prompt: help me create a Flutter service that manages estimate data in Firestore with real-time updates and status tracking
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/estimate.dart';
import '../../models/invoice.dart';

/// manages estimate data in firestore with real-time updates and status tracking
class EstimateService {
  EstimateService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('estimates');
  static final DocumentReference<Map<String, dynamic>> _ownerSettingsDoc =
      _firestore.collection('owner_settings').doc('default');

  static String _formatEstimateNumber(int n) => 'EST-${n.toString().padLeft(4, '0')}';

  /// preview the next estimate number without consuming it (used to prefill the create form)
  static Future<String> peekNextEstimateNumber() async {
    final snapshot = await _ownerSettingsDoc.get();
    final current = (snapshot.data()?['next_estimate_number'] as num?)?.toInt() ?? 1;
    return _formatEstimateNumber(current);
  }

  /// atomically read-and-increment the next estimate number counter
  static Future<String> consumeNextEstimateNumber() {
    return _firestore.runTransaction<String>((transaction) async {
      final snapshot = await transaction.get(_ownerSettingsDoc);
      final current = (snapshot.data()?['next_estimate_number'] as num?)?.toInt() ?? 1;
      transaction.set(
        _ownerSettingsDoc,
        {'next_estimate_number': current + 1},
        SetOptions(merge: true),
      );
      return _formatEstimateNumber(current);
    });
  }

  /// listen to real-time estimate updates, filtered by role and clientId
  static Stream<List<Estimate>> watchEstimates({required String role, String? clientId}) {
    Query<Map<String, dynamic>> query = _collection;
    if (role == 'client' && clientId != null && clientId.trim().isNotEmpty) {
      query = query.where('clientId', isEqualTo: clientId.trim());
    }

    return query.snapshots().map((snapshot) {
      final estimates = snapshot.docs.map((doc) {
        final data = doc.data();
        return Estimate.fromMap({...data, 'id': doc.id});
      }).where((e) => role == 'owner' || !e.isArchived).toList();
      estimates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return estimates;
    });
  }
/// archive an estimate to hide it from active lists
  
  static Future<void> archiveEstimate(String estimateId) async {
    await _collection.doc(estimateId).set(
      {'archived': true, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  /// owner action: permanently remove an archived estimate, refusing if it
  /// still has an invoice or scheduled job on file
  static Future<void> deleteEstimatePermanently(String estimateId) async {
    final normalizedId = estimateId.trim();
    final firestore = FirebaseFirestore.instance;

    final guards = {
      'invoices': const MapEntry('sourceEstimateId', 'an invoice'),
      'scheduled_work': const MapEntry('estimateId', 'a scheduled job'),
    };
    for (final entry in guards.entries) {
      final match = await firestore
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
/// create a new estimate with services and auto-calculated total
  
  static Future<void> createEstimate({
    required String estimateNumber,
    required String clientId,
    required List<InvoiceServiceItem> services,
  }) async {
    final now = DateTime.now();
    final total = services.fold<double>(0, (runningTotal, item) => runningTotal + item.price);
    final doc = _collection.doc();

    final estimate = Estimate(
      id: doc.id,
      estimateNumber: estimateNumber.trim(),
      clientId: clientId.trim(),
      services: services,
      total: total,
      status: InvoiceStatus.pending,
      createdAt: now,
      updatedAt: now,
      convertedToInvoice: false,
      revisionNumber: 1,
    );

    await doc.set(estimate.toMap());
  /// request changes on estimate from client with a message
  }

  static Future<void> requestChanges({
    required String estimateId,
    required String message,
  }) async {
    await _collection.doc(estimateId).set(
      {
        'status': InvoiceStatus.changesRequested,
        'changeRequestMessage': message.trim(),
        'changeRequestedAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  /// revise estimate with new services and increase revision number for re-sending
  }

  static Future<void> reviseAndResendEstimate({
    required Estimate estimate,
    required List<InvoiceServiceItem> services,
  }) async {
    final now = DateTime.now();
    final total = services.fold<double>(0, (runningTotal, item) => runningTotal + item.price);
    final currentSnapshot = EstimateVersionSnapshot(
      version: estimate.revisionNumber,
      services: estimate.services,
      total: estimate.total,
      status: estimate.status,
      updatedAt: estimate.updatedAt,
    );

    final originalVersionPayload =
        (estimate.originalVersion ?? currentSnapshot).toMap();

    await _collection.doc(estimate.id).set(
      {
        'services': services.map((item) => item.toMap()).toList(),
        'total': total,
        'status': InvoiceStatus.pending,
        'revisionNumber': estimate.revisionNumber + 1,
        'resentAt': now,
        'updatedAt': now,
        'changeRequestMessage': null,
        'changeRequestedAt': null,
        'originalVersion': originalVersionPayload,
      },
      SetOptions(merge: true),
  /// update estimate status to pending, approved, rejected, etc
    );
  }

  /// owner action: approve a pending estimate on the client's behalf after
  /// getting confirmation by phone or text outside the app
  static Future<void> approveByOwner({
    required String estimateId,
    required String method,
    String note = '',
  }) async {
    await _collection.doc(estimateId).set(
      {
        'status': InvoiceStatus.approved,
        'approvedByOwner': true,
        'ownerApprovalMethod': method,
        'ownerApprovalNote': note.trim(),
        'ownerApprovedAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> updateStatus({required String estimateId, required String status}) async {
    await _collection.doc(estimateId).set(
      {
        'status': status,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
  /// mark estimate as converted to invoice with the linked invoice id
    );
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
  /// fetch a single estimate by id
      SetOptions(merge: true),
    );
  }

  static Future<Estimate?> fetchById(String estimateId) async {
    final normalizedId = estimateId.trim();
    if (normalizedId.isEmpty) return null;
    final snapshot = await _collection.doc(normalizedId).get();
    final data = snapshot.data();
  /// mark estimate as scheduled to a work order
    if (!snapshot.exists || data == null) return null;
    return Estimate.fromMap({...data, 'id': snapshot.id});
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
}
