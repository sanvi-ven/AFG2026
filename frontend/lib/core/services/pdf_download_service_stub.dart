import 'dart:typed_data';

Future<String?> downloadPdfBytesImpl({
  required Uint8List bytes,
  required String fileName,
}) {
  throw UnsupportedError('PDF download is not supported on this platform.');
}
