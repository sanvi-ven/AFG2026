import 'csv_download_service_stub.dart'
    if (dart.library.html) 'csv_download_service_web.dart'
    if (dart.library.io) 'csv_download_service_io.dart';

/// download csv text to device with platform-specific implementation
Future<String?> downloadCsvBytes({
  required String csvText,
  required String fileName,
}) {
  return downloadCsvBytesImpl(csvText: csvText, fileName: fileName);
}
