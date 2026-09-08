import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/employee_profile.dart';
import '../../models/employment_contract.dart';
import '../../models/owner_settings.dart';
import 'employee_profile_service.dart';
import 'owner_settings_service.dart';
import 'pdf_download_service.dart';
import 'pdf_layout_helpers.dart';

/// generates and downloads a signed employment contract as a PDF, mirroring
/// estimate_pdf_service.dart's structure/letterhead. The contract's own
/// `# `/`## `/`- `/`**bold**` mini-markup (same rules LegalDocumentBody
/// renders for the in-app view) needs its own small pw.Widget renderer here
/// — the two can't share code since one targets Flutter's widget tree and
/// this one targets the pdf package's.
class ContractPdfService {
  ContractPdfService._();

  static Future<String?> generateAndDownloadContractPdf({
    required EmploymentContract contract,
  }) async {
    final bytes = await buildContractPdf(contract: contract);

    EmployeeProfile? employee;
    try {
      employee = await EmployeeProfileService.fetchBySignupId(contract.employeeId);
    } catch (_) {
      employee = null;
    }

    final namePart = PdfLayoutHelpers.sanitizeFilePart(
        employee?.fullName.trim().isNotEmpty == true ? employee!.fullName : contract.employeeId);
    final fileName = 'Employment_Contract_${namePart}_v${contract.contractVersion}.pdf';
    return downloadPdfBytes(bytes: bytes, fileName: fileName);
  }

  static Future<Uint8List> buildContractPdf({required EmploymentContract contract}) async {
    OwnerSettings ownerSettings;
    try {
      ownerSettings = await OwnerSettingsService.fetch();
    } catch (_) {
      ownerSettings = OwnerSettings.empty();
    }

    EmployeeProfile? employee;
    try {
      employee = await EmployeeProfileService.fetchBySignupId(contract.employeeId);
    } catch (_) {
      employee = null;
    }

    final logoBytes = await PdfLayoutHelpers.resolveLogoBytes(
        ownerSettings.logoBase64, ownerSettings.logoUrl);
    final employeeName = employee?.fullName.trim().isNotEmpty == true
        ? employee!.fullName
        : contract.employeeId;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: PdfLayoutHelpers.pageTheme(),
        footer: (context) => PdfLayoutHelpers.footer(context, ownerSettings: ownerSettings),
        build: (context) => <pw.Widget>[
          PdfLayoutHelpers.buildLetterhead(ownerSettings: ownerSettings, logoBytes: logoBytes),
          pw.SizedBox(height: 18),
          pw.Text(
            'EMPLOYMENT CONTRACT',
            style: pw.TextStyle(
                fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfLayoutHelpers.accentColor),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Employee: $employeeName'),
          pw.Text('Version: ${contract.contractVersion}'),
          pw.SizedBox(height: 18),
          ..._renderMarkup(contract.content),
          pw.SizedBox(height: 24),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          pw.Text('Signatures',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfLayoutHelpers.accentColor)),
          pw.SizedBox(height: 8),
          _signatureBlock('Employee', contract.employeeSignature),
          if (contract.guardianRequired) ...[
            pw.SizedBox(height: 12),
            _signatureBlock('Parent/Guardian', contract.guardianSignature),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _signatureBlock(String role, ContractSignature? signature) {
    if (signature == null) {
      return pw.Text('$role: not yet signed', style: const pw.TextStyle(fontSize: 10));
    }
    final dateText = DateFormat('MMM d, yyyy · h:mm a').format(signature.signedAt);
    final signatureWidget = signature.method == ContractSignatureMethod.drawn &&
            signature.drawingBase64.isNotEmpty
        ? pw.Container(
            height: 50,
            constraints: const pw.BoxConstraints(maxWidth: 220),
            child: pw.Image(pw.MemoryImage(base64Decode(signature.drawingBase64))),
          )
        : pw.Text(
            signature.typedName.isEmpty ? '(signed)' : signature.typedName,
            style: pw.TextStyle(fontSize: 20, fontStyle: pw.FontStyle.italic),
          );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$role:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        signatureWidget,
        pw.SizedBox(height: 4),
        pw.Text('Signed $dateText via ${signature.method}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    );
  }

  /// parallel to LegalDocumentBody's Flutter-widget renderer, same block
  /// rules: "# " title, "## " heading, "- " bullet, "**text**" bold, blank
  /// line = new paragraph.
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
