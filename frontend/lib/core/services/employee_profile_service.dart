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
      profiles.sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
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
    final query = await _collection
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
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
    final payload = profile
        .copyWith(employeeId: normalizedId, email: normalizedEmail)
        .toMap()
      ..addAll({'updated_at': FieldValue.serverTimestamp()});

    await _collection.doc(normalizedId).set(payload, SetOptions(merge: true));

    final saved = await fetchBySignupId(normalizedId);
    return saved ??
        profile.copyWith(employeeId: normalizedId, email: normalizedEmail);
  }

  /// look up an employee profile by their linked Firebase Auth uid
  static Future<EmployeeProfile?> fetchByUid(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return null;

    final query =
        await _collection.where('uid', isEqualTo: normalizedUid).limit(1).get();
    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    return EmployeeProfile.fromMap({...doc.data(), 'id': doc.id});
  }

  /// owner action: activate/deactivate an employee account
  static Future<void> setActive(String employeeId, bool active) async {
    await _collection
        .doc(employeeId.trim())
        .set({'active': active}, SetOptions(merge: true));
  }

  /// owner action: assign (or clear) an employee's current team
  static Future<void> assignTeam(String employeeId, String? teamId) async {
    await _collection
        .doc(employeeId.trim())
        .set({'teamId': teamId}, SetOptions(merge: true));
  }

  /// owner action: set (or clear) an employee's hourly pay rate
  static Future<void> setHourlyRate(String employeeId, double? rate) async {
    await _collection
        .doc(employeeId.trim())
        .set({'hourly_rate': rate}, SetOptions(merge: true));
  }

  /// owner action: hide an employee from the active roster and from new
  /// job/team assignments without deleting their history — their jobs, time
  /// entries, and pay records all stay on file and still resolve through
  /// this profile.
  static Future<void> archiveEmployee(String employeeId) async {
    await _collection
        .doc(employeeId.trim())
        .set({'archived': true}, SetOptions(merge: true));
  }

  /// owner action: restore a previously archived employee to the active roster
  static Future<void> unarchiveEmployee(String employeeId) async {
    await _collection
        .doc(employeeId.trim())
        .set({'archived': false}, SetOptions(merge: true));
  }

  /// set (or clear) an employee's date of birth — owner or the employee
  /// themselves (see firestore.rules); an owner-facing prompt still catches
  /// the case where this was never set at all (see ContractsTab._issueContract).
  static Future<void> setDateOfBirth(String employeeId, DateTime? dob) async {
    await _collection
        .doc(employeeId.trim())
        .set({'date_of_birth': dob}, SetOptions(merge: true));
  }

  /// set an employee's parent/guardian contact info (used for the contract
  /// co-sign flow when the employee is a minor) — owner, or the employee
  /// themselves (self-editable as of 2026-09-08, see firestore.rules and
  /// EmployeeProfile's doc comment for the accepted tradeoff this creates).
  static Future<void> setGuardianContact(
    String employeeId, {
    String? name,
    String? email,
    String? phone,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['guardian_name'] = name.trim();
    if (email != null) payload['guardian_email'] = email.trim();
    if (phone != null) payload['guardian_phone'] = phone.trim();
    if (payload.isEmpty) return;
    await _collection.doc(employeeId.trim()).set(payload, SetOptions(merge: true));
  }

  /// self-service: an employee updates their own address and/or allergy
  /// info. Owner can also call this (e.g. entering it on someone's behalf).
  static Future<void> updatePersonalInfo(
    String employeeId, {
    String? address,
    String? foodAllergies,
    String? medicationAllergies,
    String? environmentalAllergies,
  }) async {
    final payload = <String, dynamic>{};
    if (address != null) payload['address'] = address.trim();
    if (foodAllergies != null) payload['food_allergies'] = foodAllergies.trim();
    if (medicationAllergies != null) {
      payload['medication_allergies'] = medicationAllergies.trim();
    }
    if (environmentalAllergies != null) {
      payload['environmental_allergies'] = environmentalAllergies.trim();
    }
    if (payload.isEmpty) return;
    await _collection.doc(employeeId.trim()).set(payload, SetOptions(merge: true));
  }
}
