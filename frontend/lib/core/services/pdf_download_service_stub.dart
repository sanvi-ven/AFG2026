import 'dart:typed_data';

/// stub: throws unsupported error for platforms without implementation
Future<String?> downloadPdfBytesImpl({
  required Uint8List bytes,
  required String fileName,
}) {
  throw UnsupportedError('PDF download is not supported on this platform.');
}
