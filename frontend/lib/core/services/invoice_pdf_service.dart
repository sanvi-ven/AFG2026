/// made with help of chatgpt 4.0, prompt: help me create a Flutter service that generates branded invoice PDFs using the pdf package and info from Firestore
library;

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/client_profile.dart';
import '../../models/invoice.dart';
import '../../models/owner_settings.dart';
import 'client_profile_service.dart';
import 'owner_settings_service.dart';
import 'pdf_download_service.dart';
import 'pdf_layout_helpers.dart';

/// generates and downloads invoice pdfs with company branding and line items
class InvoicePdfService {
  InvoicePdfService._();

  /// standard payment window, shown as "Payment due by" on the PDF
  static const invoiceDueDays = 14;

  /// generate invoice pdf and trigger download, named per the owner's
  /// configured invoice file-name template
  static Future<String?> generateAndDownloadInvoicePdf(
      {required Invoice invoice}) async {
    final bytes = await buildInvoicePdf(invoice: invoice);

    OwnerSettings ownerSettings;
    try {
      ownerSettings = await OwnerSettingsService.fetch();
    } catch (_) {
      ownerSettings = OwnerSettings.empty();
    }

    ClientProfile? client;
    try {
      client = await ClientProfileService.fetchBySignupId(invoice.clientId);
    } catch (_) {
      client = null;
    }

    final invoicePart = invoice.invoiceNumber.trim().isEmpty
        ? invoice.id
        : invoice.invoiceNumber.trim();
    final resolved = PdfLayoutHelpers.resolveFileNameTemplate(
      ownerSettings.invoiceFileNameTemplate,
      {
        'CompanyName': ownerSettings.companyName.trim().isEmpty
            ? 'Business'
            : ownerSettings.companyName.trim(),
        'InvoiceNumber': invoicePart,
        'ClientName': client?.fullName.trim().isEmpty ?? true
            ? invoice.clientId
            : client!.fullName.trim(),
        'Date': DateFormat('yyyy-MM-dd').format(invoice.createdAt),
      },
    );
    final fileName = '${PdfLayoutHelpers.sanitizeFilePart(resolved)}.pdf';
    return downloadPdfBytes(bytes: bytes, fileName: fileName);
  }

  /// build invoice pdf document with company header, client info, items
  /// table, and total
  static Future<Uint8List> buildInvoicePdf({required Invoice invoice}) async {
    OwnerSettings ownerSettings;
    try {
      ownerSettings = await OwnerSettingsService.fetch();
    } catch (_) {
      ownerSettings = OwnerSettings.empty();
    }

    ClientProfile? client;
    try {
      client = await ClientProfileService.fetchBySignupId(invoice.clientId);
    } catch (_) {
      client = null;
    }

    final logoBytes = await PdfLayoutHelpers.resolveLogoBytes(
        ownerSettings.logoBase64, ownerSettings.logoUrl);
    final currency = PdfLayoutHelpers.currency;
    final createdDate = DateFormat('MMM d, yyyy').format(invoice.createdAt);
    final dueDate = DateFormat('MMM d, yyyy')
        .format(invoice.createdAt.add(const Duration(days: invoiceDueDays)));

    final isPaid = invoice.status == InvoiceStatus.paid;
    const watermarkColor = PdfColor(0.1, 0.5, 0.2, 0.25);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: PdfLayoutHelpers.pageTheme(
          watermarkText: isPaid ? 'PAID' : null,
          watermarkColor: watermarkColor,
        ),
        footer: (context) =>
            PdfLayoutHelpers.footer(context, ownerSettings: ownerSettings),
        build: (context) => <pw.Widget>[
          PdfLayoutHelpers.buildLetterhead(
              ownerSettings: ownerSettings, logoBytes: logoBytes),
          pw.SizedBox(height: 18),
          pw.Text(
            'INVOICE',
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
                      client: client, fallbackClientId: invoice.clientId)),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Invoice #: ${invoice.invoiceNumber}'),
                    pw.Text('Issued: $createdDate'),
                    if (!isPaid) pw.Text('Payment due by: $dueDate'),
                    pw.Text('Status: ${_capitalizeStatus(invoice.status)}'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          PdfLayoutHelpers.buildItemsTable(
            headers: const <String>['Line Item', 'Amount'],
            data: invoice.services.map((item) {
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
              child: pw.Text(
                'Total: ${currency.format(invoice.total)}',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
          if (invoice.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Notes',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfLayoutHelpers.accentColor)),
            pw.Text(invoice.notes.trim()),
          ],
          if (invoice.terms.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Terms',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfLayoutHelpers.accentColor)),
            pw.Text(invoice.terms.trim()),
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
