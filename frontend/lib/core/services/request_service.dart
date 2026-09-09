import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/request.dart';
import 'comms_service.dart';
import 'owner_settings_service.dart';

/// manages work requests — the pre-estimate intake pipeline. Creation has no
/// auth guard (mirrors ClientProfileService.createSignup) since brand-new,
/// not-yet-signed-up leads need to be able to submit one too.
class RequestService {
  RequestService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('requests');

  /// stream all requests, newest first
  static Stream<List<Request>> watchAllRequests() {
    return _collection.snapshots().map((snapshot) {
      final requests = snapshot.docs.map((doc) => Request.fromMap({...doc.data(), 'id': doc.id})).toList();
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

  /// mint a doc id up front so photos can be uploaded to a stable storage
  /// path (request_photos/{id}/) before the request document itself exists
  static String newRequestId() => _collection.doc().id;

  static Future<void> createRequest({
    required String id,
    String? clientId,
    required String name,
    required String email,
    required String phone,
    required String address,
    required String description,
    List<String> photoUrls = const [],
    bool smsOptIn = false,
    String preferredContact = PreferredContactMethod.email,
  }) async {
    final request = Request(
      id: id,
      clientId: clientId,
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      address: address.trim(),
      description: description.trim(),
      photoUrls: photoUrls,
      status: RequestStatus.newRequest,
      createdAt: DateTime.now(),
      smsOptIn: smsOptIn,
      preferredContact: preferredContact,
    );
    await _collection.doc(id).set(request.toMap());
  }

  /// fetch a single request by id — used to carry its phone/smsOptIn
  /// forward when converting it into a client record (see
  /// QuickAddClientDialog's prefill support)
  static Future<Request?> fetchById(String requestId) async {
    final normalizedId = requestId.trim();
    if (normalizedId.isEmpty) return null;
    final snapshot = await _collection.doc(normalizedId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return Request.fromMap({...data, 'id': snapshot.id});
  }

  static Future<void> markConverted({required String requestId, required String estimateId}) async {
    await _collection.doc(requestId).set(
      {'status': RequestStatus.converted, 'convertedEstimateId': estimateId},
      SetOptions(merge: true),
    );
  }

  /// owner action, so the existing owner-authenticated CommsService.sendSms
  /// (raw body, not the pre-auth template path) is the right call here —
  /// unlike the request-received confirmation, which fires from the public,
  /// not-yet-signed-in form.
  static Future<void> markDeclined({required String requestId, String reason = ''}) async {
    await _collection.doc(requestId).set(
      {'status': RequestStatus.declined, 'declineReason': reason.trim()},
      SetOptions(merge: true),
    );

    try {
      final request = await fetchById(requestId);
      final phone = request?.phone.trim() ?? '';
      if (request != null && phone.isNotEmpty && request.smsOptIn) {
        final ownerSettings = await OwnerSettingsService.fetch();
        final businessName =
            ownerSettings.companyName.trim().isEmpty ? 'Your service provider' : ownerSettings.companyName.trim();
        await CommsService.sendSms(
          to: phone,
          body: "$businessName: Thanks for reaching out. We're not able to take on this request "
              'right now. Reply STOP to opt out.',
        );
      }
    } catch (_) {
      // best-effort, same reasoning as every other fire-and-forget comms
      // call in this app
    }
  }
}
