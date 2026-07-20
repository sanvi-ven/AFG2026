/// shared layout building blocks for the estimate/invoice PDFs, so both
/// documents look like one consistent, professional system instead of two
/// independently-drifting copies.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/client_profile.dart';
import '../../models/owner_settings.dart';

class PdfLayoutHelpers {
  PdfLayoutHelpers._();

  /// deep forest green accent, fitting a landscaping business — a fixed
  /// visual upgrade over the previous plain black/gray, not owner-configurable.
  static const accentColor = PdfColor.fromInt(0xFF2E5339);
  static final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

  /// resolve logo bytes from base64, url, or local asset fallback in priority order
  static Future<Uint8List?> resolveLogoBytes(
      String? logoBase64, String? logoUrl) async {
    if (logoBase64 != null && logoBase64.isNotEmpty) {
      try {
        return base64Decode(logoBase64);
      } catch (_) {
        // fall through
      }
    }

    final remoteUrl = logoUrl?.trim() ?? '';
    if (remoteUrl.isNotEmpty) {
      try {
        final response = await http
            .get(Uri.parse(remoteUrl))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
      } catch (_) {
        // fall through
      }
    }

    try {
      final localAsset = await rootBundle.load('assets/logos/logo.png');
      return localAsset.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// letterhead: logo + company name/address/phone/email
  static pw.Widget buildLetterhead(
      {required OwnerSettings ownerSettings, Uint8List? logoBytes}) {
    final companyName = ownerSettings.companyName.trim().isEmpty
        ? 'Business Name'
        : ownerSettings.companyName.trim();
    final companyAddress = ownerSettings.address.trim().isEmpty
        ? 'Business address unavailable'
        : ownerSettings.address.trim();
    final contactLine = [ownerSettings.phone.trim(), ownerSettings.email.trim()]
        .where((value) => value.isNotEmpty)
        .join('   ·   ');

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null)
          pw.Container(
            width: 72,
            height: 72,
            margin: const pw.EdgeInsets.only(right: 16),
            child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: accentColor),
              ),
              pw.SizedBox(height: 4),
              pw.Text(companyAddress, style: const pw.TextStyle(fontSize: 10)),
              if (contactLine.isNotEmpty)
                pw.Text(contactLine, style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  /// "Bill To" block; falls back to the raw client id if the profile
  /// couldn't be resolved (deleted client, fetch failure, etc.)
  static pw.Widget buildBillTo(
      {required ClientProfile? client, required String fallbackClientId}) {
    final lines = <String>[];
    if (client != null) {
      lines.add(client.fullName.trim().isEmpty
          ? fallbackClientId
          : client.fullName.trim());
      if (client.address.trim().isNotEmpty) lines.add(client.address.trim());
      if (client.phoneNumber.trim().isNotEmpty) {
        lines.add(client.phoneNumber.trim());
      }
      if (client.email.trim().isNotEmpty) lines.add(client.email.trim());
    } else {
      lines.add('Client ID: $fallbackClientId');
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'BILL TO',
          style: pw.TextStyle(
              fontSize: 10, fontWeight: pw.FontWeight.bold, color: accentColor),
        ),
        pw.SizedBox(height: 4),
        for (final line in lines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  /// page theme carrying the standard letter format/margin, plus an optional
  /// large diagonal translucent status stamp (e.g. APPROVED/DECLINED/PAID)
  /// painted as the page background.
  static pw.PageTheme pageTheme(
      {String? watermarkText,
      PdfColor watermarkColor = const PdfColor(0.7, 0.1, 0.1, 0.28)}) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(28),
      buildBackground: watermarkText == null
          ? null
          : (context) => pw.Center(
                child: pw.Watermark.text(
                  watermarkText,
                  angle: 0.5,
                  style: pw.TextStyle(
                      color: watermarkColor,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 90),
                ),
              ),
    );
  }

  /// footer: a thin divider, a thank-you note, contact info, and page numbers
  static pw.Widget footer(pw.Context context,
      {required OwnerSettings ownerSettings}) {
    final contactLine = [ownerSettings.phone.trim(), ownerSettings.email.trim()]
        .where((value) => value.isNotEmpty)
        .join('   ·   ');

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Divider(color: PdfColors.grey300, height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Thank you for your business!',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            if (contactLine.isNotEmpty)
              pw.Text(contactLine,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ],
    );
  }

  /// shared restyled items table: bordered, alternating row shading, accent
  /// header, and a fixed-width Amount column so its header/prices never wrap
  static pw.Widget buildItemsTable(
      {required List<String> headers, required List<List<String>> data}) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
      headerDecoration: const pw.BoxDecoration(color: accentColor),
      oddRowDecoration:
          const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F6F3)),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      cellStyle: const pw.TextStyle(fontSize: 10),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.5),
        1: pw.FixedColumnWidth(85),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
      },
    );
  }

  /// replace `{Key}` placeholders in a file-name template with their values
  static String resolveFileNameTemplate(
      String template, Map<String, String> values) {
    var result = template;
    values.forEach((key, value) => result = result.replaceAll('{$key}', value));
    return result;
  }

  static String sanitizeFilePart(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'document';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
