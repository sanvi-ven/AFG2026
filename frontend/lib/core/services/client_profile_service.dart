//made with the help of chatgpt 4.0; prompt: create a flutter service class for firestore that manages a client profile model

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/client_profile.dart';

/// characters used for claim codes; ambiguous-looking characters (0/O, 1/I) are excluded
const String _claimCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// manages client profile data in firestore
/// provides methods for reading, searching, and updating client profiles
class ClientProfileService {
  ClientProfileService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _signupsCollection =
      _firestore.collection('client_signups');

  /// convert email to lowercase and trim whitespace for consistent lookups
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

  /// search profiles by firstName, lastName, email, address, or signupId
  /// excludes profiles in the excludeSignupIds set and limits results
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

  /// search profiles by email with normalized lookup
  static Future<ClientProfile?> fetchByEmail(String email) async {
    final normalizedEmail = normalizeEmail(email);
    final query = await _signupsCollection.where('email', isEqualTo: normalizedEmail).limit(1).get();
    if (query.docs.isEmpty) {
      return null;
    }

    final doc = query.docs.first;
    return ClientProfile.fromMap(doc.data()).copyWith(signupId: doc.id);
  }

  /// save or update a client profile in firestore
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

  /// look up a client profile by their linked Firebase Auth uid
  static Future<ClientProfile?> fetchByUid(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return null;

    final query = await _signupsCollection.where('uid', isEqualTo: normalizedUid).limit(1).get();
    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    return ClientProfile.fromMap(doc.data()).copyWith(signupId: doc.id);
  }

  /// owner action: create a client record for someone who won't use the app
  /// themselves — no email/password required up front. Gets a placeholder
  /// email until the account is claimed (see generateClaimCode). Doc id is
  /// Firestore's own auto-generated id, not a scanned sequential counter —
  /// computing a "next" id used to mean reading every existing client's full
  /// record (including their password hash) just to create one new one.
  static Future<ClientProfile> createDummyClient({
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String address,
  }) async {
    final doc = _signupsCollection.doc();
    final resolvedEmail = 'client.${doc.id}@no-login.internal';

    final profile = ClientProfile(
      signupId: doc.id,
      email: resolvedEmail,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phoneNumber: phoneNumber.trim(),
      address: address.trim(),
    );

    await doc.set({
      ...profile.toMap(),
      'created_at': FieldValue.serverTimestamp(),
    });

    return profile;
  }

  /// change a client's email, rejecting the change if another account already uses it
  static Future<void> updateEmail(String signupId, String newEmail) async {
    final normalizedId = signupId.trim();
    final normalizedEmail = normalizeEmail(newEmail);

    final existing = await fetchByEmail(normalizedEmail);
    if (existing != null && existing.signupId != normalizedId) {
      throw Exception('That email is already used by another account.');
    }

    await _signupsCollection.doc(normalizedId).set({'email': normalizedEmail}, SetOptions(merge: true));
  }

  static final Random _claimCodeRandom = Random();

  static String _generateClaimCode() {
    return List.generate(
      6,
      (_) => _claimCodeAlphabet[_claimCodeRandom.nextInt(_claimCodeAlphabet.length)],
    ).join();
  }

  /// owner action: generate (or regenerate) a one-time code the owner reads out
  /// to a dummy client so they can claim their account with a real email/password
  static Future<String> generateClaimCode(String signupId) async {
    final code = _generateClaimCode();
    await _signupsCollection.doc(signupId.trim()).set({
      'claim_code': code,
      'claim_code_created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return code;
  }

  /// look up the dummy client account a claim code belongs to
  static Future<ClientProfile?> fetchByClaimCode(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) return null;

    final query = await _signupsCollection.where('claim_code', isEqualTo: normalizedCode).limit(1).get();
    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    return ClientProfile.fromMap(doc.data()).copyWith(signupId: doc.id);
  }

  /// consume a claim code once the account has been successfully claimed
  static Future<void> clearClaimCode(String signupId) async {
    await _signupsCollection.doc(signupId.trim()).set({
      'claim_code': FieldValue.delete(),
      'claim_code_created_at': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  /// resolve a clientId to a display name for sorting/labeling; falls back to the id itself
  static String displayNameFor(List<ClientProfile> profiles, String clientId) {
    for (final profile in profiles) {
      if (profile.signupId == clientId) {
        return profile.fullName;
      }
    }
    return clientId;
  }

  /// owner action: hide a client from active use without deleting their history
  static Future<void> archiveClient(String signupId) async {
    await _signupsCollection.doc(signupId.trim()).set({'archived': true}, SetOptions(merge: true));
  }

  /// owner action: permanently remove an archived client, refusing if they
  /// still have estimates, invoices, or scheduled jobs on file
  static Future<void> deleteClientPermanently(String signupId) async {
    final normalizedId = signupId.trim();
    final firestore = FirebaseFirestore.instance;

    final linkedCollections = {
      'estimates': 'estimates',
      'invoices': 'invoices',
      'scheduled_work': 'scheduled jobs',
    };
    for (final entry in linkedCollections.entries) {
      final match = await firestore
          .collection(entry.key)
          .where('clientId', isEqualTo: normalizedId)
          .limit(1)
          .get();
      if (match.docs.isNotEmpty) {
        throw Exception(
          "This client still has ${entry.value} on file and can't be permanently deleted.",
        );
      }
    }

    await _signupsCollection.doc(normalizedId).delete();
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
