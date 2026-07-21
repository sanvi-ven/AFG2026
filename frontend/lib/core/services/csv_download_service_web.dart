// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

/// download csv text as browser blob on web platform
Future<String?> downloadCsvBytesImpl({
  required String csvText,
  required String fileName,
}) async {
  if (csvText.isEmpty) {
    throw Exception('Cannot download an empty CSV.');
  }

  final normalizedFileName = fileName.trim().isEmpty ? 'export.csv' : fileName.trim();
  final bytes = utf8.encode(csvText);
  final blob = html.Blob(<dynamic>[bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = normalizedFileName
    ..target = '_blank'
    ..rel = 'noopener'
    ..style.display = 'none';
  (html.document.body ?? html.document.documentElement)?.append(anchor);
  anchor.click();
  anchor.remove();

  // delay url take back so browsers have time to start the download.
  await Future<void>.delayed(const Duration(seconds: 1));
  html.Url.revokeObjectUrl(url);
  return null;
}
