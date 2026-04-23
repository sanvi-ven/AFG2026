//made with the help of chatgpt; prompt: create a flutter service class for firestore that manages a client profile model

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/client_profile.dart';

class ClientProfileService {
  ClientProfileService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _signupsCollection =
      _firestore.collection('client_signups');

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static Stream<List<ClientProfile>> watchAllProfiles() {
    return _signupsCollection.snapshots().map((snapshot) {
      final profiles = snapshot.docs
          .map((doc) => ClientProfile.fromMap(doc.data()).copyWith(signupId: doc.id))
          .where((profile) => profile.signupId.trim().isNotEmpty)
          .toList();
      profiles.sort((a, b) => a.signupId.compareTo(b.signupId));
      return profiles;
    });
  }

  static List<ClientProfile> searchProfiles({
    required List<ClientProfile> profiles,
    required String query,
    int limit = 8,
    Set<String> excludeSignupIds = const <String>{},
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <ClientProfile>[];
    }

    final matches = profiles.where((profile) {
      if (excludeSignupIds.contains(profile.signupId)) {
        return false;
      }

      final searchable = <String>[
        profile.signupId,
        profile.fullName,
        profile.firstName,
        profile.lastName,
        profile.address,
        profile.email,
      ].map((value) => value.trim().toLowerCase()).where((value) => value.isNotEmpty);

      for (final value in searchable) {
        if (value.contains(normalizedQuery)) {
          return true;
        }
      }

      return false;
    }).toList();

    if (matches.length > limit) {
      return matches.sublist(0, limit);
    }
    return matches;
  }

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
    String phoneNumber = '',
    String address = '',
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
        phoneNumber: phoneNumber.trim().isNotEmpty ? phoneNumber : existing.phoneNumber,
        address: address.trim().isNotEmpty ? address : existing.address,
      );

      final hasChanges = merged.email != existing.email ||
          merged.firstName != existing.firstName ||
          merged.lastName != existing.lastName ||
          merged.phoneNumber != existing.phoneNumber ||
          merged.address != existing.address;

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
      phoneNumber: phoneNumber,
      address: address,
    );
    return save(profile);
  }
}
