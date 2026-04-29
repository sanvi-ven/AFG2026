//made with the help of chatgpt; prompt: create a flutter service class for firestore that manages a client profile model

import 'dart:math';

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

  /// Creates a brand-new client signup directly in Firestore, replicating the
  /// logic that was previously handled by the FastAPI backend POST endpoint.
  /// Returns the newly created [ClientProfile].
  static Future<String?> fetchPasswordHash(String email) async {
    final normalizedEmail = normalizeEmail(email);
    final query = await _signupsCollection.where('email', isEqualTo: normalizedEmail).limit(1).get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.data()['password_hash'] as String?;
  }

  static Future<void> updatePasswordHash({
    required String email,
    required String passwordHash,
  }) async {
    final normalizedEmail = normalizeEmail(email);
    final query = await _signupsCollection.where('email', isEqualTo: normalizedEmail).limit(1).get();
    if (query.docs.isEmpty) throw Exception('Client not found.');
    await _signupsCollection.doc(query.docs.first.id).update({'password_hash': passwordHash});
  }

  static Future<ClientProfile> createSignup({
    required String email,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String address,
    String? passwordHash,
  }) async {
    final normalizedEmail = normalizeEmail(email);

    // Reject duplicate emails.
    final existing = await fetchByEmail(normalizedEmail);
    if (existing != null) {
      throw Exception('An account with that email address already exists.');
    }

    // Determine the next sequential 5-digit client ID.
    final allDocs = await _signupsCollection.get();
    int maxSeen = 0;
    for (final doc in allDocs.docs) {
      final candidate = doc.id.trim();
      if (candidate.length == 5) {
        final parsed = int.tryParse(candidate);
        if (parsed != null) maxSeen = max(maxSeen, parsed);
      }
    }
    final nextValue = maxSeen + 1;
    if (nextValue > 99999) {
      throw Exception('Client signup capacity reached (99999).');
    }
    final newId = nextValue.toString().padLeft(5, '0');

    final profile = ClientProfile(
      signupId: newId,
      email: normalizedEmail,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phoneNumber: phoneNumber.trim(),
      address: address.trim(),
    );

    await _signupsCollection.doc(newId).set({
      ...profile.toMap(),
      'created_at': FieldValue.serverTimestamp(),
      if (passwordHash != null) 'password_hash': passwordHash,
    });

    return profile;
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
