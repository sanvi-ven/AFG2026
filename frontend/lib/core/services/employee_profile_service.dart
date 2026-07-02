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

  static Future<String?> fetchPasswordHash(String email) async {
    final normalizedEmail = normalizeEmail(email);
    final query = await _collection.where('email', isEqualTo: normalizedEmail).limit(1).get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.data()['password_hash'] as String?;
  }

  static Future<void> updatePasswordHash({
    required String email,
    required String passwordHash,
  }) async {
    final normalizedEmail = normalizeEmail(email);
    final query = await _collection.where('email', isEqualTo: normalizedEmail).limit(1).get();
    if (query.docs.isEmpty) throw Exception('Employee not found.');
    await _collection.doc(query.docs.first.id).update({'password_hash': passwordHash});
  }

  /// create a new employee signup with profile and password hash
  static Future<EmployeeProfile> createSignup({
    required String email,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    String? passwordHash,
  }) async {
    final normalizedEmail = normalizeEmail(email);

    final existing = await fetchByEmail(normalizedEmail);
    if (existing != null) {
      throw Exception('An account with that email address already exists.');
    }

    final doc = _collection.doc();
    final profile = EmployeeProfile(
      employeeId: doc.id,
      email: normalizedEmail,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phoneNumber: phoneNumber.trim(),
      teamId: null,
      active: true,
    );

    await doc.set({
      ...profile.toMap(),
      'created_at': FieldValue.serverTimestamp(),
      if (passwordHash != null) 'password_hash': passwordHash,
    });

    return profile;
  }

  /// owner action: activate/deactivate an employee account
  static Future<void> setActive(String employeeId, bool active) async {
    await _collection.doc(employeeId.trim()).set({'active': active}, SetOptions(merge: true));
  }

  /// owner action: assign (or clear) an employee's current team
  static Future<void> assignTeam(String employeeId, String? teamId) async {
    await _collection.doc(employeeId.trim()).set({'teamId': teamId}, SetOptions(merge: true));
  }
}
