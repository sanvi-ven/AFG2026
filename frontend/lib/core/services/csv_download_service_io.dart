import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// download csv text to device file system on mobile and desktop platforms
Future<String?> downloadCsvBytesImpl({
  required String csvText,
  required String fileName,
}) async {
  Directory? targetDirectory;
  try {
    targetDirectory = await getDownloadsDirectory();
  } catch (_) {
    targetDirectory = null;
  }
  targetDirectory ??= await getApplicationDocumentsDirectory();

  final trimmedName = fileName.trim().isEmpty ? 'export.csv' : fileName.trim();
  final sanitizedName = trimmedName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File('${targetDirectory.path}/$sanitizedName');
  await file.writeAsBytes(utf8.encode(csvText), flush: true);
  return file.path;
}
