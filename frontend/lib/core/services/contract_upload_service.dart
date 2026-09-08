import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';

/// uploads a scan/photo or PDF of an already-signed paper employment
/// contract — the one folder backend/app/api/v1/routes/photos.py accepts a
/// real PDF for, not just an image (see that file's own doc comment).
class ContractUploadService {
  ContractUploadService._();

  static final ImagePicker _picker = ImagePicker();
  static final Random _random = Random();

  static String _uniqueFileName(String extension) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 31);
    return '${stamp}_$suffix.$extension';
  }

  static Future<String?> _uploadBytes({
    required List<int> bytes,
    required String employeeId,
    required String extension,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/photos/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['folder'] = 'contract_documents/${employeeId.trim()}'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: _uniqueFileName(extension),
      ));

    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['url'] as String?;
  }

  /// prompt the owner to pick a photo of a signed paper contract (from their
  /// gallery — most such photos are already taken/scanned by the time this
  /// runs), then upload it under contract_documents/{employeeId}/. Returns
  /// the hosted url, or null if the picker was cancelled.
  static Future<String?> pickAndUploadPaperContract({
    required String employeeId,
  }) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    return _uploadBytes(bytes: bytes, employeeId: employeeId, extension: 'jpg');
  }

  /// prompt the owner to pick a PDF of a signed paper contract from their
  /// files, then upload it the same way. Returns the hosted url, or null if
  /// the picker was cancelled.
  static Future<String?> pickAndUploadPaperContractPdf({
    required String employeeId,
  }) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();

    return _uploadBytes(bytes: bytes, employeeId: employeeId, extension: 'pdf');
  }
}
