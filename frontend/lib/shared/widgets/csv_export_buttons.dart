import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/services/csv_download_service.dart';
import '../utils/csv_utils.dart';

/// Reusable pair of export controls for any table of rows. [rows] must already
/// include the header as its first row (caller's responsibility). Both buttons
/// disable themselves when there's nothing to export (no data rows beyond the
/// header), so a user never silently exports an empty/header-only file.
class ExportButtons extends StatelessWidget {
  const ExportButtons({required this.rows, required this.fileNamePrefix, super.key});

  final List<List<Object?>> rows;
  final String fileNamePrefix;

  /// header-only (or empty) means there's no real data to export
  bool get _hasData => rows.length > 1;

  Future<void> _downloadCsv(BuildContext context) async {
    try {
      final csvText = buildDelimitedText(rows);
      final fileName = '${fileNamePrefix}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final savedPath = await downloadCsvBytes(csvText: csvText, fileName: fileName);
      if (!context.mounted) return;
      final message = savedPath == null ? 'CSV downloaded.' : 'CSV saved: $savedPath';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _copy(BuildContext context) async {
    try {
      // tab-delimited pastes as separate columns in Google Sheets/Excel
      final text = buildDelimitedText(rows, delimiter: '\t');
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _hasData ? () => _downloadCsv(context) : null,
          icon: const Icon(Icons.download),
          label: const Text('Download CSV'),
        ),
        OutlinedButton.icon(
          onPressed: _hasData ? () => _copy(context) : null,
          icon: const Icon(Icons.copy),
          label: const Text('Copy'),
        ),
      ],
    );
  }
}
