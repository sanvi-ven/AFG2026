// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:typed_data';
import 'dart:html' as html;

Future<String?> downloadPdfBytesImpl({
  required Uint8List bytes,
  required String fileName,
}) async {
  if (bytes.isEmpty) {
    throw Exception('Cannot download an empty PDF.');
  }

  final normalizedFileName = fileName.trim().isEmpty ? 'document.pdf' : fileName.trim();
  final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = normalizedFileName
    ..target = '_blank'
    ..rel = 'noopener'
    ..style.display = 'none';
  (html.document.body ?? html.document.documentElement)?.append(anchor);
  anchor.click();
  anchor.remove();

  // Delay URL revocation so browsers have time to start the download.
  await Future<void>.delayed(const Duration(seconds: 1));
  html.Url.revokeObjectUrl(url);
  return null;
}
