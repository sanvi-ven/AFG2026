import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/client_profile.dart';
import '../../models/fall_cleanup_estimate.dart';
import '../../models/owner_settings.dart';
import 'client_profile_service.dart';
import 'owner_settings_service.dart';
import 'pdf_download_service.dart';
import 'pdf_layout_helpers.dart';

/// generates and downloads fall cleanup estimate pdfs, mirroring
/// estimate_pdf_service.dart's letterhead/footer/filename structure. The
/// frozen policy text uses the same `# `/`## `/`- `/`**bold**` mini-markup
/// LegalDocumentBody renders in-app — see ContractPdfService for why that
/// renderer can't be shared directly with the Flutter widget tree version.
class FallCleanupPdfService {
  FallCleanupPdfService._();

  static Future<String?> generateAndDownloadFallCleanupPdf(
      {required FallCleanupEstimate estimate}) async {
    final bytes = await buildFallCleanupPdf(estimate: estimate);

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
      ownerSettings.fallCleanupFileNameTemplate,
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

  static Future<Uint8List> buildFallCleanupPdf(
      {required FallCleanupEstimate estimate}) async {
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

    final watermarkText = estimate.isSigned ? 'APPROVED' : null;
    const watermarkColor = PdfColor(0.1, 0.5, 0.2, 0.25);

    final planRows = <List<String>>[];
    for (final plan in FallCleanupPlan.all) {
      final price = estimate.priceFor(plan);
      planRows.add([
        FallCleanupPlan.displayLabel(plan) +
            (estimate.selectedPlan == plan ? '  ✓ Selected' : ''),
        price == null ? 'Not offered for this property' : currency.format(price),
      ]);
    }

    final additionalWorkAmount = estimate.additionalWorkAmount;
    final additionalWorkText = estimate.additionalWorkNeedsQuote
        ? 'Separate quote upon request.'
        : (additionalWorkAmount == null || additionalWorkAmount == 0)
            ? 'None'
            : '${estimate.additionalWorkDescription.trim().isEmpty ? 'Additional work' : estimate.additionalWorkDescription.trim()} — ${currency.format(additionalWorkAmount)}';

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
            'FALL CLEANUP ESTIMATE',
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
                    pw.Text('Status: ${_statusLabel(estimate)}'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('Plans',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfLayoutHelpers.accentColor)),
          pw.SizedBox(height: 6),
          PdfLayoutHelpers.buildItemsTable(
            headers: const <String>['Plan', 'Price'],
            data: planRows,
          ),
          pw.SizedBox(height: 14),
          pw.Text('Leaf Disposal',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfLayoutHelpers.accentColor)),
          pw.Text(
            estimate.disposalFee > 0
                ? '${FallCleanupDisposalChoice.displayLabel(estimate.disposalChoice)} — ${currency.format(estimate.disposalFee)}'
                : FallCleanupDisposalChoice.displayLabel(estimate.disposalChoice),
          ),
          if (estimate.whereLeavesCanGo.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text('Where leaves can go',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfLayoutHelpers.accentColor)),
            pw.Text(estimate.whereLeavesCanGo.trim()),
          ],
          pw.SizedBox(height: 14),
          pw.Text('Additional Work',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfLayoutHelpers.accentColor)),
          pw.Text(additionalWorkText),
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
                estimate.selectedPlan == null
                    ? 'No plan selected yet'
                    : 'Total: ${currency.format(estimate.total)}',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
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
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF3F6F3),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Confirmation Summary',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: PdfLayoutHelpers.accentColor)),
                pw.SizedBox(height: 4),
                pw.Text(
                    'Client: ${client?.fullName.trim().isNotEmpty == true ? client!.fullName.trim() : estimate.clientId}'),
                if (client?.address.trim().isNotEmpty == true)
                  pw.Text('Service address: ${client!.address.trim()}'),
                pw.Text(
                    'Package: ${estimate.selectedPlan == null ? 'pending selection' : FallCleanupPlan.displayLabel(estimate.selectedPlan!)}'),
                pw.Text(
                    'Disposal choice: ${FallCleanupDisposalChoice.displayLabel(estimate.disposalChoice)}'),
                if (estimate.whereLeavesCanGo.trim().isNotEmpty)
                  pw.Text('Where leaves can go: ${estimate.whereLeavesCanGo.trim()}'),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          ..._renderMarkup(estimate.policyContent),
          if (estimate.isSigned) ...[
            pw.SizedBox(height: 16),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 6),
            pw.Text(
              estimate.approvedByOwner
                  ? 'Approved — ${DateFormat('MMM d, yyyy').format(estimate.ownerApprovedAt ?? estimate.updatedAt)} (confirmed via ${estimate.ownerApprovalMethod ?? 'phone'})'
                  : 'Approved — ${DateFormat('MMM d, yyyy').format(estimate.updatedAt)}',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
            ),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  static String _statusLabel(FallCleanupEstimate estimate) {
    if (estimate.isSigned) return 'Approved';
    if (estimate.isChangesRequested) return 'Changes requested';
    return 'Pending';
  }

  /// parallel to LegalDocumentBody's Flutter-widget renderer and
  /// ContractPdfService's own copy, same block rules: "# " title, "## "
  /// heading, "- " bullet, "**text**" bold, blank line = new paragraph.
  static List<pw.Widget> _renderMarkup(String content) {
    final blocks = content.split('\n\n');
    final widgets = <pw.Widget>[];

    for (final block in blocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('# ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Text(trimmed.substring(2).trim(),
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        ));
        continue;
      }
      if (trimmed.startsWith('## ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(trimmed.substring(3).trim(),
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ));
        continue;
      }

      final lines = trimmed.split('\n');
      if (lines.every((line) => line.trimLeft().startsWith('- '))) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('•  ', style: const pw.TextStyle(fontSize: 10)),
                      pw.Expanded(
                        child: pw.RichText(
                          text: pw.TextSpan(
                              children: _inlineBold(line.trimLeft().substring(2).trim())),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ));
        continue;
      }

      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.RichText(text: pw.TextSpan(children: _inlineBold(trimmed))),
      ));
    }

    return widgets;
  }

  static List<pw.InlineSpan> _inlineBold(String text) {
    final spans = <pw.InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var lastEnd = 0;
    const baseStyle = pw.TextStyle(fontSize: 10);
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(pw.TextSpan(text: text.substring(lastEnd, match.start), style: baseStyle));
      }
      spans.add(pw.TextSpan(
          text: match.group(1), style: baseStyle.copyWith(fontWeight: pw.FontWeight.bold)));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(pw.TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }
    return spans;
  }
}
