//made using https://firebase.google.com/docs/reference/js/firestore_

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/invoice.dart';
import 'client_profile_service.dart';
import 'comms_service.dart';
import 'owner_settings_service.dart';

/// manages invoice data in firestore with real-time updates and conversions
class InvoiceService {
  InvoiceService._();

  /// best-effort SMS to the client, gated on their own smsOptIn — same
  /// business-name + STOP format registered with Twilio's A2P campaign as
  /// every other transactional SMS in this app (see
  /// reminder_check_service.dart / scheduled_work_service.dart). Never
  /// throws — a failed/skipped send must never block the write it follows.
  static Future<void> _notifyClient(String clientId, String Function(String businessName) buildBody) async {
    try {
      final client = await ClientProfileService.fetchBySignupId(clientId);
      if (client == null) return;
      final phone = client.phoneNumber.trim();
      if (phone.isEmpty || !client.smsOptIn) return;

      final ownerSettings = await OwnerSettingsService.fetch();
      final businessName =
          ownerSettings.companyName.trim().isEmpty ? 'Your service provider' : ownerSettings.companyName.trim();

      await CommsService.sendSms(to: phone, body: buildBody(businessName));
    } catch (_) {
      // best-effort, same reasoning as every other fire-and-forget comms
      // call in this app
    }
  }

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
      }).where((invoice) => role == 'owner' || !invoice.isArchived).toList();
      invoices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return invoices;
    });
  }

  /// owner action: hide an invoice from active use without deleting its history
  static Future<void> archiveInvoice(String invoiceId) async {
    await _collection.doc(invoiceId).set(
      {'archived': true, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  /// owner action: permanently remove an archived invoice, refusing if it's
  /// still linked to a scheduled job
  static Future<void> deleteInvoicePermanently(String invoiceId) async {
    final normalizedId = invoiceId.trim();
    final match = await FirebaseFirestore.instance
        .collection('scheduled_work')
        .where('invoiceId', isEqualTo: normalizedId)
        .limit(1)
        .get();
    if (match.docs.isNotEmpty) {
      throw Exception(
        "This invoice is still linked to a scheduled job and can't be permanently deleted.",
      );
    }

    await _collection.doc(normalizedId).delete();
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
    String notes = '',
    String terms = '',
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
      notes: notes.trim(),
      terms: terms.trim(),
    );

    await doc.set(invoice.toMap());
    unawaited(_notifyClient(
      invoice.clientId,
      (businessName) => '$businessName: A new invoice (${invoice.invoiceNumber}) for '
          '\$${invoice.total.toStringAsFixed(2)} is ready. Log in to your account to view it. '
          'Reply STOP to opt out.',
    ));
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
    final normalizedStatus = status.trim();
    // fetched before the write so a paid->paid no-op (e.g. a duplicate
    // click) doesn't re-send a receipt the client already got
    final existing = await getInvoiceById(invoiceId);

    await _collection.doc(invoiceId).set(
      {
        'status': normalizedStatus,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );

    final justPaid =
        normalizedStatus == InvoiceStatus.paid && existing != null && existing.status != InvoiceStatus.paid;
    if (justPaid) {
      unawaited(_notifyClient(
        existing.clientId,
        (businessName) => "$businessName: Thank you! We've received your payment for Invoice "
            '${existing.invoiceNumber} (\$${existing.total.toStringAsFixed(2)}). Reply STOP to opt out.',
      ));
    }
  }

  /// stamp that an overdue-invoice reminder notification has been created,
  /// so [ReminderCheckService] doesn't create a duplicate
  static Future<void> markReminderSent(String invoiceId) async {
    await _collection.doc(invoiceId).set(
      {'lastReminderSentAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }
}
