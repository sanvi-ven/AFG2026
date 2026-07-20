/// made with help of chatgpt 4.0, prompt: help me create a Flutter service that generates branded estimate PDFs using the pdf package
library;

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/client_profile.dart';
import '../../models/estimate.dart';
import '../../models/owner_settings.dart';
import 'client_profile_service.dart';
import 'owner_settings_service.dart';
import 'pdf_download_service.dart';
import 'pdf_layout_helpers.dart';

/// generates and downloads estimate pdfs with company branding and estimate details
class EstimatePdfService {
  EstimatePdfService._();

  /// how long a quoted price is honored, shown as "Valid until" on the PDF
  static const estimateValidityDays = 30;

  /// generates estimate pdf and downloads it, named per the owner's
  /// configured estimate file-name template
  static Future<String?> generateAndDownloadEstimatePdf(
      {required Estimate estimate}) async {
    final bytes = await buildEstimatePdf(estimate: estimate);

    OwnerSettings ownerSettings;
    try {
      ownerSettings = await OwnerSettingsService.fetch();
    } catch (_) {
      ownerSettings = OwnerSettings.empty();
    }

    ClientProfile? client;
    try {
      client = await ClientProfileService.fetchBySignupId(estimate.clientId);
    } catch (_) {
      client = null;
    }

    final part = estimate.estimateNumber.trim().isEmpty
        ? estimate.id
        : estimate.estimateNumber.trim();
    final resolved = PdfLayoutHelpers.resolveFileNameTemplate(
      ownerSettings.estimateFileNameTemplate,
      {
        'CompanyName': ownerSettings.companyName.trim().isEmpty
            ? 'Business'
            : ownerSettings.companyName.trim(),
        'EstimateNumber': part,
        'ClientName': client?.fullName.trim().isEmpty ?? true
            ? estimate.clientId
            : client!.fullName.trim(),
        'Date': DateFormat('yyyy-MM-dd').format(estimate.createdAt),
      },
    );
    final fileName = '${PdfLayoutHelpers.sanitizeFilePart(resolved)}.pdf';
    return downloadPdfBytes(bytes: bytes, fileName: fileName);
  }

  /// builds complete pdf with company header, client info, estimate details,
  /// services table, and total
  static Future<Uint8List> buildEstimatePdf(
      {required Estimate estimate}) async {
    OwnerSettings ownerSettings;
    try {
      ownerSettings = await OwnerSettingsService.fetch();
    } catch (_) {
      ownerSettings = OwnerSettings.empty();
    }

    ClientProfile? client;
    try {
      client = await ClientProfileService.fetchBySignupId(estimate.clientId);
    } catch (_) {
      client = null;
    }

    final logoBytes = await PdfLayoutHelpers.resolveLogoBytes(
        ownerSettings.logoBase64, ownerSettings.logoUrl);
    final currency = PdfLayoutHelpers.currency;
    final createdDate = DateFormat('MMM d, yyyy').format(estimate.createdAt);
    final validUntil = DateFormat('MMM d, yyyy').format(
        estimate.createdAt.add(const Duration(days: estimateValidityDays)));

    final watermarkText = estimate.isApproved
        ? 'APPROVED'
        : estimate.isDenied
            ? 'DECLINED'
            : null;
    final watermarkColor = estimate.isApproved
        ? const PdfColor(0.1, 0.5, 0.2, 0.25)
        : const PdfColor(0.7, 0.1, 0.1, 0.28);

    final depositPercent = estimate.depositPercent;
    final depositAmount =
        depositPercent != null ? estimate.total * depositPercent / 100 : null;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: PdfLayoutHelpers.pageTheme(
            watermarkText: watermarkText, watermarkColor: watermarkColor),
        footer: (context) =>
            PdfLayoutHelpers.footer(context, ownerSettings: ownerSettings),
        build: (context) => <pw.Widget>[
          PdfLayoutHelpers.buildLetterhead(
              ownerSettings: ownerSettings, logoBytes: logoBytes),
          pw.SizedBox(height: 18),
          pw.Text(
            'ESTIMATE',
            style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfLayoutHelpers.accentColor),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                  child: PdfLayoutHelpers.buildBillTo(
                      client: client, fallbackClientId: estimate.clientId)),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Estimate #: ${estimate.estimateNumber}'),
                    pw.Text('Issued: $createdDate'),
                    pw.Text('Valid until: $validUntil'),
                    pw.Text('Status: ${_capitalizeStatus(estimate.status)}'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          PdfLayoutHelpers.buildItemsTable(
            headers: const <String>['Line Item', 'Amount'],
            data: estimate.services.map((item) {
              final lines = <String>[item.name];
              if (item.description.isNotEmpty) lines.add(item.description);
              if (item.isPerUnit) {
                lines.add(
                    '${item.quantity} ${item.unit ?? 'unit'} x ${currency.format(item.unitPrice!)}');
              }
              return <String>[lines.join('\n'), currency.format(item.price)];
            }).toList(),
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfLayoutHelpers.accentColor, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Total: ${currency.format(estimate.total)}',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  if (depositAmount != null) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Deposit due to begin work (${depositPercent!.toStringAsFixed(0)}%): '
                      '${currency.format(depositAmount)}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (estimate.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Notes',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfLayoutHelpers.accentColor)),
            pw.Text(estimate.notes.trim()),
          ],
          if (estimate.terms.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Terms',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfLayoutHelpers.accentColor)),
            pw.Text(estimate.terms.trim()),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  /// capitalize first letter of status string
  static String _capitalizeStatus(String status) {
    final s = status.trim();
    if (s.isEmpty) return 'Pending';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }
}
