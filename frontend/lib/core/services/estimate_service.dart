import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/estimate.dart';
import '../../models/invoice.dart';

class EstimateService {
  EstimateService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('estimates');

  static Stream<List<Estimate>> watchEstimates({required String role, String? clientId}) {
    Query<Map<String, dynamic>> query = _collection;
    if (role == 'client' && clientId != null && clientId.trim().isNotEmpty) {
      query = query.where('clientId', isEqualTo: clientId.trim());
    }

    return query.snapshots().map((snapshot) {
      final estimates = snapshot.docs.map((doc) {
        final data = doc.data();
        return Estimate.fromMap({...data, 'id': doc.id});
      }).toList();
      estimates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return estimates;
    });
  }

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
    );

    await doc.set(estimate.toMap());
  }

  static Future<void> updateStatus({required String estimateId, required String status}) async {
    await _collection.doc(estimateId).set(
      {
        'status': status,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
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
      SetOptions(merge: true),
    );
  }
}
