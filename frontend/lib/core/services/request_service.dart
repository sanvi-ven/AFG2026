import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/request.dart';

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
    );
    await _collection.doc(id).set(request.toMap());
  }

  static Future<void> markConverted({required String requestId, required String estimateId}) async {
    await _collection.doc(requestId).set(
      {'status': RequestStatus.converted, 'convertedEstimateId': estimateId},
      SetOptions(merge: true),
    );
  }

  static Future<void> markDeclined({required String requestId, String reason = ''}) async {
    await _collection.doc(requestId).set(
      {'status': RequestStatus.declined, 'declineReason': reason.trim()},
      SetOptions(merge: true),
    );
  }
}
