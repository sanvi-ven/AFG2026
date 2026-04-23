import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String?> downloadPdfBytesImpl({
  required Uint8List bytes,
  required String fileName,
}) async {
  Directory? targetDirectory;
  try {
    targetDirectory = await getDownloadsDirectory();
  } catch (_) {
    targetDirectory = null;
  }
  targetDirectory ??= await getApplicationDocumentsDirectory();

  final sanitizedName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File('${targetDirectory.path}/$sanitizedName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
