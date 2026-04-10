import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/client_profile.dart';

class ClientProfileService {
  ClientProfileService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _profilesCollection =
      _firestore.collection('client_profiles');

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static Future<ClientProfile?> fetchByEmail(String email) async {
    final normalizedEmail = normalizeEmail(email);
    final snapshot = await _profilesCollection.doc(normalizedEmail).get();
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();
    if (data == null) {
      return null;
    }

    return ClientProfile.fromMap(data);
  }

  static Future<ClientProfile> save(ClientProfile profile) async {
    final normalizedEmail = normalizeEmail(profile.email);
    final payload = profile.copyWith(email: normalizedEmail).toMap()
      ..addAll({'updatedAt': FieldValue.serverTimestamp()});

    await _profilesCollection.doc(normalizedEmail).set(payload, SetOptions(merge: true));

    final saved = await fetchByEmail(normalizedEmail);
    return saved ?? profile.copyWith(email: normalizedEmail);
  }

  static Future<ClientProfile> getOrCreate(String email) async {
    final normalizedEmail = normalizeEmail(email);
    final existing = await fetchByEmail(normalizedEmail);
    if (existing != null) {
      return existing;
    }

    final profile = ClientProfile.emptyForEmail(normalizedEmail);
    return save(profile);
  }
}
