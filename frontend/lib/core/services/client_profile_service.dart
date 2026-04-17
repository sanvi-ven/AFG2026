//made with the help of chatgpt; prompt: create a flutter service class for firestore that manages a client profile model

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/client_profile.dart';

class ClientProfileService {
  ClientProfileService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _signupsCollection =
      _firestore.collection('client_signups');

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static Future<ClientProfile?> fetchBySignupId(String signupId) async {
    final normalizedId = signupId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }

    final snapshot = await _signupsCollection.doc(normalizedId).get();
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();
    if (data == null) {
      return null;
    }

    return ClientProfile.fromMap(data).copyWith(signupId: normalizedId);
  }

  static Future<ClientProfile?> fetchByEmail(String email) async {
    final normalizedEmail = normalizeEmail(email);
    final query = await _signupsCollection.where('email', isEqualTo: normalizedEmail).limit(1).get();
    if (query.docs.isEmpty) {
      return null;
    }

    final doc = query.docs.first;
    return ClientProfile.fromMap(doc.data()).copyWith(signupId: doc.id);
  }

  static Future<ClientProfile> save(ClientProfile profile) async {
    final normalizedId = profile.signupId.trim();
    if (normalizedId.isEmpty) {
      throw Exception('Client signup ID is required to save profile.');
    }

    final normalizedEmail = normalizeEmail(profile.email);
    final payload = profile.copyWith(signupId: normalizedId, email: normalizedEmail).toMap()
      ..addAll({'updatedAt': FieldValue.serverTimestamp()});

    await _signupsCollection.doc(normalizedId).set(payload, SetOptions(merge: true));

    final saved = await fetchBySignupId(normalizedId);
    return saved ?? profile.copyWith(signupId: normalizedId, email: normalizedEmail);
  }

  static Future<ClientProfile> getOrCreateForSignup({
    required String signupId,
    required String email,
    String firstName = '',
    String lastName = '',
    String phone = '',
    String street = '',
    String country = '',
    String zipCode = '',
  }) async {
    final normalizedId = signupId.trim();
    if (normalizedId.isEmpty) {
      throw Exception('Client signup ID is required.');
    }

    final existing = await fetchBySignupId(normalizedId);
    if (existing != null) {
      final merged = existing.copyWith(
        email: email.trim().isNotEmpty ? email : existing.email,
        firstName: firstName.trim().isNotEmpty ? firstName : existing.firstName,
        lastName: lastName.trim().isNotEmpty ? lastName : existing.lastName,
        phone: phone.trim().isNotEmpty ? phone : existing.phone,
        street: street.trim().isNotEmpty ? street : existing.street,
        country: country.trim().isNotEmpty ? country : existing.country,
        zipCode: zipCode.trim().isNotEmpty ? zipCode : existing.zipCode,
      );

      final hasChanges = merged.email != existing.email ||
          merged.firstName != existing.firstName ||
          merged.lastName != existing.lastName ||
          merged.phone != existing.phone ||
          merged.street != existing.street ||
          merged.country != existing.country ||
          merged.zipCode != existing.zipCode;

      if (hasChanges) {
        return save(merged);
      }
      return merged;
    }

    final profile = ClientProfile(
      signupId: normalizedId,
      email: email,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      street: street,
      country: country,
      zipCode: zipCode,
    );
    return save(profile);
  }
}
