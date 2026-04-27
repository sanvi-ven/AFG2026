import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/invoice.dart';
import '../../models/scheduled_work.dart';

class ScheduledWorkService {
  ScheduledWorkService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('scheduled_work');

  static Stream<List<ScheduledWork>> watchScheduledWork({
    required String role,
    String? clientId,
  }) {
    Query<Map<String, dynamic>> query = _collection;
    if (role == 'client' && clientId != null && clientId.trim().isNotEmpty) {
      query = query.where('clientId', isEqualTo: clientId.trim());
    }

    return query.snapshots().map((snapshot) {
      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        return ScheduledWork.fromMap({...data, 'id': doc.id});
      }).toList();
      items.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      return items;
    });
  }

  static Future<String> createScheduledWork({
    required String estimateId,
    required String estimateNumber,
    required String clientId,
    required List<InvoiceServiceItem> services,
    required double total,
    required DateTime scheduledDate,
  }) async {
    final now = DateTime.now();
    final doc = _collection.doc();

    final work = ScheduledWork(
      id: doc.id,
      estimateId: estimateId.trim(),
      estimateNumber: estimateNumber.trim(),
      clientId: clientId.trim(),
      services: services,
      total: total,
      scheduledDate: scheduledDate,
      status: ScheduledWorkStatus.scheduled,
      createdAt: now,
      updatedAt: now,
    );

    await doc.set(work.toMap());
    return doc.id;
  }

  static Future<void> markCompleted({required String workId}) async {
    await _collection.doc(workId).set(
      {
        'status': ScheduledWorkStatus.completed,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> markInvoiced({
    required String workId,
    required String invoiceId,
  }) async {
    await _collection.doc(workId).set(
      {
        'status': ScheduledWorkStatus.invoiced,
        'invoiceId': invoiceId.trim(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }
}
