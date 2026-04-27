import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/estimate.dart';
import '../../models/owner_settings.dart';
import 'owner_settings_service.dart';
import 'pdf_download_service.dart';

class EstimatePdfService {
  EstimatePdfService._();

  static Future<String?> generateAndDownloadEstimatePdf({required Estimate estimate}) async {
    final bytes = await buildEstimatePdf(estimate: estimate);
    final part = estimate.estimateNumber.trim().isEmpty ? estimate.id : estimate.estimateNumber.trim();
    final fileName = 'estimate_${_sanitizeFilePart(part)}.pdf';
    return downloadPdfBytes(bytes: bytes, fileName: fileName);
  }

  static Future<Uint8List> buildEstimatePdf({required Estimate estimate}) async {
    OwnerSettings ownerSettings;
    try {
      ownerSettings = await OwnerSettingsService.fetch();
    } catch (_) {
      ownerSettings = OwnerSettings.empty();
    }

    final logoBytes = await _resolveLogoBytes(ownerSettings.logoUrl);
    final companyName = ownerSettings.companyName.trim().isEmpty
        ? 'Business Name'
        : ownerSettings.companyName.trim();
    final companyAddress = ownerSettings.address.trim().isEmpty
        ? 'Business address unavailable'
        : ownerSettings.address.trim();

    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
    final createdDate = DateFormat('yyyy-MM-dd').format(estimate.createdAt);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => <pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoBytes != null)
                pw.Container(
                  width: 80,
                  height: 80,
                  margin: const pw.EdgeInsets.only(right: 16),
                  child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(companyAddress, style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'ESTIMATE',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Estimate #: ${estimate.estimateNumber}'),
          pw.Text('Client ID: ${estimate.clientId}'),
          pw.Text('Created: $createdDate'),
          pw.Text('Status: ${_capitalizeStatus(estimate.status)}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Line Item', 'Amount'],
            data: estimate.services
                .map((item) => <String>[item.name, currency.format(item.price)])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAEAEA)),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total: ${currency.format(estimate.total)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List?> _resolveLogoBytes(String? logoUrl) async {
    final remoteUrl = logoUrl?.trim() ?? '';
    if (remoteUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 15));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
      } catch (_) {
        // Fall through to local fallback asset.
      }
    }

    try {
      final localAsset = await rootBundle.load('assets/logos/logo.png');
      return localAsset.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static String _capitalizeStatus(String status) {
    final s = status.trim();
    if (s.isEmpty) return 'Pending';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  static String _sanitizeFilePart(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'document';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
