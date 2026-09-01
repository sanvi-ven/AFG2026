import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';

/// uploads before/after job-completion photos through the backend, which
/// forwards them to Cloudinary (the Cloudinary API secret can't live in the
/// Flutter client, so this can't upload directly the way Firebase Storage
/// used to)
class JobPhotoUploadService {
  JobPhotoUploadService._();

  static final ImagePicker _picker = ImagePicker();
  static final Random _random = Random();

  static String _uniqueFileName() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 31);
    return '${stamp}_$suffix.jpg';
  }

  static Future<String?> _uploadBytes({
    required List<int> bytes,
    required String folder,
    bool requireAuth = true,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/photos/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['folder'] = folder
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: _uniqueFileName(),
      ));

    if (requireAuth) {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Photo upload failed (${response.statusCode}): ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['url'] as String?;
  }

  /// prompt the user to pick an image, then upload it under job_photos/{workId}/{phase}/
  /// returns the hosted url, or null if the user cancelled the picker
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
    return _uploadBytes(bytes: bytes, folder: 'job_photos/$workId/$phase');
  }

  /// prompt the user to pick an image from their gallery, then upload it
  /// under request_photos/{requestId}/ — gallery (not camera) since this is
  /// used from the public/client-facing "request work" form, not a field crew.
  /// returns the hosted url, or null if the user cancelled the picker
  static Future<String?> pickAndUploadRequestPhoto({required String requestId}) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    return _uploadBytes(bytes: bytes, folder: 'request_photos/$requestId', requireAuth: false);
  }

  /// prompt the user to take a photo, then upload it under
  /// equipment_photos/{equipmentId}/ — camera (not gallery) since equipment
  /// photos are of a physical on-site asset, like job photos.
  /// returns the hosted url, or null if the user cancelled the picker
  static Future<String?> pickAndUploadEquipmentPhoto({
    required String equipmentId,
  }) async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    return _uploadBytes(bytes: bytes, folder: 'equipment_photos/$equipmentId');
  }
}
