import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/owner_settings.dart';

class OwnerSettingsService {
  OwnerSettingsService._();

  static const String _docId = 'default';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('owner_settings');

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

  static Future<String> uploadLogo({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final extension = _fileExtensionForMimeType(mimeType);
    final path = 'owner_settings/$_docId/logo_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(contentType: mimeType);

    await ref.putData(bytes, metadata);
    return ref.getDownloadURL();
  }

  static String _fileExtensionForMimeType(String mimeType) {
    final normalized = mimeType.trim().toLowerCase();
    if (normalized == 'image/png') {
      return 'png';
    }
    if (normalized == 'image/webp') {
      return 'webp';
    }
    if (normalized == 'image/gif') {
      return 'gif';
    }
    return 'jpg';
  }
}
