import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/owner_settings.dart';

/// manages owner company settings and branding stored in firestore
class OwnerSettingsService {
  OwnerSettingsService._();

  static const String _docId = 'default';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('owner_settings');

  /// fetch the current owner settings from firestore
  static Future<OwnerSettings> fetch() async {
    final snapshot = await _collection.doc(_docId).get();
    final data = snapshot.data();
    if (data == null) {
      return OwnerSettings.empty();
    }
    return OwnerSettings.fromMap(data);
  }

  static Future<OwnerSettings> save(OwnerSettings settings) async {
    final payload = settings.toMap()
      ..addAll({'updated_at': FieldValue.serverTimestamp()});

    await _collection.doc(_docId).set(payload, SetOptions(merge: true));
    return fetch();
  }
}
