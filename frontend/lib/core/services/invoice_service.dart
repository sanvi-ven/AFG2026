//made using https://firebase.google.com/docs/reference/js/firestore_

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/invoice.dart';

/// manages invoice data in firestore with real-time updates and conversions
class InvoiceService {
  InvoiceService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('invoices');

  /// listen to real-time invoice updates, filtered by role and clientId
  static Stream<List<Invoice>> watchInvoices({required String role, String? clientId}) {
    Query<Map<String, dynamic>> query = _collection;
    if (role == 'client' && clientId != null && clientId.trim().isNotEmpty) {
      query = query.where('clientId', isEqualTo: clientId.trim());
    }

    return query.snapshots().map((snapshot) {
      final invoices = snapshot.docs.map((doc) {
        final data = doc.data();
        return Invoice.fromMap({...data, 'id': doc.id});
      }).toList();
      invoices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return invoices;
    });
  }

  /// create a new invoice with services and auto-calculated total
  static Future<void> createInvoice({
    required String invoiceNumber,
    required String clientId,
    required List<InvoiceServiceItem> services,
    String status = InvoiceStatus.pending,
    String? sourceEstimateId,
  }) async {
    final now = DateTime.now();
    final total = services.fold<double>(0, (runningTotal, item) => runningTotal + item.price);
    final doc = _collection.doc();

    final invoice = Invoice(
      id: doc.id,
      invoiceNumber: invoiceNumber.trim(),
      clientId: clientId.trim(),
      services: services,
      total: total,
      status: status,
      createdAt: now,
      updatedAt: now,
      sourceEstimateId: sourceEstimateId?.trim(),
    );

    await doc.set(invoice.toMap());
  }

  /// create a new invoice from an approved estimate and return the invoice id
  static Future<String> createInvoiceFromEstimate({
    required String invoiceNumber,
    required String clientId,
    required List<InvoiceServiceItem> services,
    required String sourceEstimateId,
  }) async {
    final now = DateTime.now();
    final total = services.fold<double>(0, (runningTotal, item) => runningTotal + item.price);
    final doc = _collection.doc();

    final invoice = Invoice(
      id: doc.id,
      invoiceNumber: invoiceNumber.trim(),
      clientId: clientId.trim(),
      services: services,
      total: total,
      status: InvoiceStatus.sent,
      createdAt: now,
      updatedAt: now,
      sourceEstimateId: sourceEstimateId.trim(),
    );

    await doc.set(invoice.toMap());
    return doc.id;
  }

  /// fetch a single invoice by id
  static Future<Invoice?> getInvoiceById(String invoiceId) async {
    final normalizedId = invoiceId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }

    final snapshot = await _collection.doc(normalizedId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return null;
    }

    return Invoice.fromMap({...data, 'id': snapshot.id});
  }

  /// update invoice status to pending, sent, paid, etc
  static Future<void> updateStatus({required String invoiceId, required String status}) async {
    await _collection.doc(invoiceId).set(
      {
        'status': status,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }
}
