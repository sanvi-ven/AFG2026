import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// uploads before/after job-completion photos to firebase storage
class JobPhotoUploadService {
  JobPhotoUploadService._();

  static final ImagePicker _picker = ImagePicker();
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final Random _random = Random();

  static String _uniqueFileName() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 32);
    return '${stamp}_$suffix.jpg';
  }

  /// prompt the user to pick an image, then upload it under job_photos/{workId}/{phase}/
  /// returns the download url, or null if the user cancelled the picker
  static Future<String?> pickAndUpload({
    required String workId,
    required String phase,
  }) async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final ref = _storage.ref('job_photos/$workId/$phase/${_uniqueFileName()}');
    final task = await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }
}
