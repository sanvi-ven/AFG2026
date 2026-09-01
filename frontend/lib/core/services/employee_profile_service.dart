import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/employee_profile.dart';

/// manages employee profile data in firestore
class EmployeeProfileService {
  EmployeeProfileService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('employee_signups');

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  /// stream the full employee roster, sorted by name
  static Stream<List<EmployeeProfile>> watchAllProfiles() {
    return _collection.snapshots().map((snapshot) {
      final profiles = snapshot.docs
          .map((doc) => EmployeeProfile.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      profiles.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      return profiles;
    });
  }

  static Future<EmployeeProfile?> fetchBySignupId(String employeeId) async {
    final normalizedId = employeeId.trim();
    if (normalizedId.isEmpty) return null;

    final snapshot = await _collection.doc(normalizedId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;

    return EmployeeProfile.fromMap({...data, 'id': normalizedId});
  }

  static Future<EmployeeProfile?> fetchByEmail(String email) async {
    final normalizedEmail = normalizeEmail(email);
    final query = await _collection.where('email', isEqualTo: normalizedEmail).limit(1).get();
    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    return EmployeeProfile.fromMap({...doc.data(), 'id': doc.id});
  }

  static Future<EmployeeProfile> save(EmployeeProfile profile) async {
    final normalizedId = profile.employeeId.trim();
    if (normalizedId.isEmpty) {
      throw Exception('Employee ID is required to save profile.');
    }

    final normalizedEmail = normalizeEmail(profile.email);
    final payload = profile.copyWith(employeeId: normalizedId, email: normalizedEmail).toMap()
      ..addAll({'updated_at': FieldValue.serverTimestamp()});

    await _collection.doc(normalizedId).set(payload, SetOptions(merge: true));

    final saved = await fetchBySignupId(normalizedId);
    return saved ?? profile.copyWith(employeeId: normalizedId, email: normalizedEmail);
  }

  /// look up an employee profile by their linked Firebase Auth uid
  static Future<EmployeeProfile?> fetchByUid(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return null;

    final query = await _collection.where('uid', isEqualTo: normalizedUid).limit(1).get();
    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    return EmployeeProfile.fromMap({...doc.data(), 'id': doc.id});
  }

  /// owner action: activate/deactivate an employee account
  static Future<void> setActive(String employeeId, bool active) async {
    await _collection.doc(employeeId.trim()).set({'active': active}, SetOptions(merge: true));
  }

  /// owner action: assign (or clear) an employee's current team
  static Future<void> assignTeam(String employeeId, String? teamId) async {
    await _collection.doc(employeeId.trim()).set({'teamId': teamId}, SetOptions(merge: true));
  }

  /// owner action: set (or clear) an employee's hourly pay rate
  static Future<void> setHourlyRate(String employeeId, double? rate) async {
    await _collection.doc(employeeId.trim()).set({'hourly_rate': rate}, SetOptions(merge: true));
  }
}
