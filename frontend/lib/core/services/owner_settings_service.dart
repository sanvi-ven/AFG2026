import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../firebase_options.dart';
import '../../models/owner_settings.dart';

class OwnerSettingsService {
  OwnerSettingsService._();

  static const String _docId = 'default';
  static const Duration _uploadTimeout = Duration(seconds: 45);
  static const Duration _downloadUrlTimeout = Duration(seconds: 20);
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instanceFor(
    bucket: DefaultFirebaseOptions.currentPlatform.storageBucket,
  );
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
    if (bytes.isEmpty) {
      throw Exception('Logo file is empty. Please choose a different image.');
    }

    final extension = _fileExtensionForMimeType(mimeType);
    final path = 'owner_settings/$_docId/logo_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(contentType: mimeType);

    final uploadTask = ref.putData(bytes, metadata);
    TaskSnapshot snapshot;
    try {
      snapshot = await uploadTask.timeout(_uploadTimeout);
    } on FirebaseException catch (error) {
      throw Exception(_friendlyStorageMessage(error));
    } on TimeoutException {
      // In some web/network scenarios the upload reaches Storage but completion
      // callback is delayed; recover by attempting to fetch the object URL.
      try {
        return await ref.getDownloadURL().timeout(_downloadUrlTimeout);
      } on Exception {
        throw Exception(
          'Logo upload timed out. Check your internet or Firebase Storage rules, then try again.',
        );
      }
    }

    try {
      return await snapshot.ref.getDownloadURL().timeout(_downloadUrlTimeout);
    } on FirebaseException catch (error) {
      throw Exception(_friendlyStorageMessage(error));
    } on TimeoutException {
      throw Exception('Upload completed, but fetching logo URL timed out. Please retry.');
    }
  }

  static String _friendlyStorageMessage(FirebaseException error) {
    switch (error.code) {
      case 'unauthorized':
        return 'Storage permission denied. Update Firebase Storage rules to allow this upload.';
      case 'object-not-found':
        return 'Storage bucket object was not found. Check your Firebase Storage bucket setup.';
      case 'canceled':
        return 'Upload canceled.';
      case 'quota-exceeded':
        return 'Firebase Storage quota exceeded.';
      default:
        return 'Storage upload failed (${error.code}): ${error.message ?? 'Unknown error'}';
    }
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
