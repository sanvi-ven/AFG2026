/// stub: throws unsupported error for platforms without implementation
Future<String?> downloadCsvBytesImpl({
  required String csvText,
  required String fileName,
}) {
  throw UnsupportedError('CSV download is not supported on this platform.');
}
