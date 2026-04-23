import 'dart:typed_data';

import 'pdf_download_service_stub.dart'
    if (dart.library.html) 'pdf_download_service_web.dart'
    if (dart.library.io) 'pdf_download_service_io.dart';

Future<String?> downloadPdfBytes({
  required Uint8List bytes,
  required String fileName,
}) {
  return downloadPdfBytesImpl(bytes: bytes, fileName: fileName);
}
