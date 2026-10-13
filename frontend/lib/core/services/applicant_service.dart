import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/applicant.dart';

/// owner-side access to job applications. Applications are only ever
/// created server-side (the website integration, via the Admin SDK) —
/// firestore.rules gives no client a create path at all.
class ApplicantService {
  ApplicantService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('applicants');

  /// stream all applications, newest first
  static Stream<List<Applicant>> watchAllApplicants() {
    return _collection.snapshots().map((snapshot) {
      final applicants =
          snapshot.docs.map((doc) => Applicant.fromMap({...doc.data(), 'id': doc.id})).toList();
      applicants.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return applicants;
    });
  }

  static Future<void> updateStatus({required String applicantId, required String status}) async {
    if (!ApplicantStatus.all.contains(status)) {
      throw ArgumentError('Unknown applicant status: $status');
    }
    await _collection.doc(applicantId).update({'status': status});
  }

  static Future<void> updateNotes({required String applicantId, required String notes}) async {
    await _collection.doc(applicantId).update({'ownerNotes': notes.trim()});
  }

  static Future<void> deleteApplicant(String applicantId) async {
    await _collection.doc(applicantId).delete();
  }
}
