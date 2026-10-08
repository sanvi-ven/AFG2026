/// the body of a Fall Cleanup estimate PDF (estimate.type == 'fall_cleanup'):
/// package and disposal cards, the optional extras table, additional work,
/// the total, notes, and terms. The letterhead, estimate info block, footer,
/// and page theme are the standard estimate's own — see EstimatePdfService.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/client_profile.dart';
import '../../models/estimate.dart';
import '../../models/fall_cleanup.dart';
import 'pdf_layout_helpers.dart';

class EstimateFallCleanupPdf {
  EstimateFallCleanupPdf._();

  static const _accent = PdfLayoutHelpers.accentColor;
  static const _border = PdfColors.grey400;
  static const _muted = PdfColors.grey700;
  static const _stripe = PdfColor.fromInt(0xFFF3F6F3);
  static const _cardGap = 10.0;

  static const _checkCircleSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
      '<circle cx="8" cy="8" r="8" fill="#ffffff"/>'
      '<path d="M4.4 8.3 L7 10.8 L11.7 5.6" stroke="#2E5339" stroke-width="1.9" '
      'fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  static const _boxCheckedSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14">'
      '<rect x="0.5" y="0.5" width="13" height="13" rx="2" fill="#2E5339" stroke="#2E5339"/>'
      '<path d="M3.4 7.2 L6 9.7 L10.6 4.5" stroke="#ffffff" stroke-width="1.7" '
      'fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  static const _boxEmptySvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14">'
      '<rect x="0.5" y="0.5" width="13" height="13" rx="2" fill="#ffffff" '
      'stroke="#555555" stroke-width="1"/></svg>';

  static String _price(double? price, {bool zeroIsIncluded = false}) {
    if (price == null) return 'Upon Request';
    if (zeroIsIncluded && price == 0) return 'Included';
    return PdfLayoutHelpers.currency.format(price);
  }

  /// Bill To with a service address line (the standard block lists the
  /// address unlabeled alongside the phone number)
  static pw.Widget billTo(
      {required ClientProfile? client, required String fallbackClientId}) {
    final lines = <String>[];
    if (client != null) {
      lines.add(client.fullName.trim().isEmpty
          ? fallbackClientId
          : client.fullName.trim());
      if (client.email.trim().isNotEmpty) lines.add(client.email.trim());
      if (client.address.trim().isNotEmpty) {
        lines.add('Service address: ${client.address.trim()}');
      }
    } else {
      lines.add('Client ID: $fallbackClientId');
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('BILL TO',
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold, color: _accent)),
        pw.SizedBox(height: 4),
        for (final line in lines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  static pw.Widget _sectionHeading(String title, String hint) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _accent)),
          if (hint.isNotEmpty) ...[
            pw.SizedBox(width: 8),
            pw.Text(hint,
                style: const pw.TextStyle(fontSize: 9, color: _muted)),
          ],
        ],
      ),
    );
  }

  /// a row of equal-width cards. Built as a table so every card stretches to
  /// the tallest one and every header shares one height (descriptions line up
  /// even when a long name wraps); wrapped in a non-spanning Container so
  /// MultiPage moves the whole row to the next page rather than splitting it.
  static pw.Widget _cardRow({
    required String title,
    required String hint,
    required List<FallCleanupOption> options,
    required Map<String, double?> prices,
    required String? selectedKey,
    bool zeroIsIncluded = false,
  }) {
    pw.Widget header(FallCleanupOption option) {
      final selected = option.key == selectedKey;
      final textColor = selected ? PdfColors.white : PdfColors.black;
      final style = pw.TextStyle(
          fontSize: 10, fontWeight: pw.FontWeight.bold, color: textColor);
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: pw.BoxDecoration(
          color: selected ? _accent : PdfColors.white,
          border: pw.Border(
            top: pw.BorderSide(
                color: selected ? _accent : _border,
                width: selected ? 1.5 : 0.8),
            left: pw.BorderSide(
                color: selected ? _accent : _border,
                width: selected ? 1.5 : 0.8),
            right: pw.BorderSide(
                color: selected ? _accent : _border,
                width: selected ? 1.5 : 0.8),
            bottom: pw.BorderSide(
                color: selected ? _accent : PdfColors.grey300, width: 0.8),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (selected) ...[
              pw.SizedBox(
                  width: 11,
                  height: 11,
                  child: pw.SvgImage(svg: _checkCircleSvg)),
              pw.SizedBox(width: 5),
            ],
            pw.Expanded(child: pw.Text(option.name, style: style)),
            pw.SizedBox(width: 6),
            pw.Text(_price(prices[option.key], zeroIsIncluded: zeroIsIncluded),
                style: style),
          ],
        ),
      );
    }

    pw.Widget body(FallCleanupOption option) {
      final selected = option.key == selectedKey;
      final side = pw.BorderSide(
          color: selected ? _accent : _border, width: selected ? 1.5 : 0.8);
      return pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 9),
        decoration: pw.BoxDecoration(
          border: pw.Border(left: side, right: side, bottom: side),
        ),
        child: pw.Text(option.description,
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.5)),
      );
    }

    final widths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < options.length * 2 - 1; i++) {
      widths[i] = i.isEven
          ? const pw.FlexColumnWidth(1)
          : const pw.FixedColumnWidth(_cardGap);
    }

    List<pw.Widget> cells(pw.Widget Function(FallCleanupOption) build) => [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) pw.SizedBox(),
            build(options[i]),
          ],
        ];

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionHeading(title, hint),
          pw.Table(
            columnWidths: widths,
            children: [
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.full,
                children: cells(header),
              ),
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.full,
                children: cells(body),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// all four extras, checked or not, in the standard Line Item / Amount
  /// table styling. Checked rows count toward the total.
  static pw.Widget _extrasTable(FallCleanupDetails details) {
    pw.Widget headerCell(String text, pw.Alignment alignment) => pw.Container(
          alignment: alignment,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: pw.Text(text,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 11)),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _accent),
        children: [
          headerCell('Extra', pw.Alignment.centerLeft),
          headerCell('Amount', pw.Alignment.centerRight),
        ],
      ),
    ];
    for (var i = 0; i < FallCleanupCatalog.extras.length; i++) {
      final option = FallCleanupCatalog.extras[i];
      final checked = details.selection.extras.contains(option.key);
      rows.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.middle,
        decoration: i.isOdd ? const pw.BoxDecoration(color: _stripe) : null,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 1, right: 8),
                  child: pw.SizedBox(
                    width: 10,
                    height: 10,
                    child: pw.SvgImage(
                        svg: checked ? _boxCheckedSvg : _boxEmptySvg),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(option.name,
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(option.description,
                          style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                _price(details.extraPrices[option.key]),
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: checked ? pw.FontWeight.bold : null),
              ),
            ),
          ),
        ],
      ));
    }

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionHeading('Optional Extras', 'Add any'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3.5),
              1: pw.FixedColumnWidth(85),
            },
            children: rows,
          ),
        ],
      ),
    );
  }

  /// breakdown of what's selected plus the total box, kept together; or,
  /// with no package picked, the "depends on your options" line instead
  static pw.Widget _total(Estimate estimate, FallCleanupDetails details) {
    if (!details.hasPackage) {
      return pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Your total depends on the options you choose.',
            style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic)),
      );
    }

    final currency = PdfLayoutHelpers.currency;
    final breakdown = <List<String>>[
      for (final line in details.selectedLines)
        [
          '${line.category}: ${line.option.name}',
          _price(line.price, zeroIsIncluded: line.category == 'Disposal'),
        ],
      if (estimate.services.isNotEmpty)
        [
          'Additional work',
          currency.format(estimate.services
              .fold<double>(0, (sum, item) => sum + item.price)),
        ],
    ];
    final totalText = 'Total: ${currency.format(estimate.total)}'
        '${details.hasUponRequestSelected ? ' + items upon request' : ''}';

    // Align fills the width so the right-aligned column actually sits on the
    // right; the outer Container keeps breakdown + box on one page
    return pw.Container(
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 230,
              child: pw.Column(
                children: [
                  for (final row in breakdown)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 3),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                              child: pw.Text(row[0],
                                  style: const pw.TextStyle(fontSize: 10))),
                          pw.Text(row[1],
                              style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _accent, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(totalText,
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  if (details.isTwoVisit &&
                      !details.hasUponRequestSelected) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Billed 50% after each visit '
                      '(${currency.format(estimate.total / 2)} per visit)',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// everything below the estimate info block
  static List<pw.Widget> body(Estimate estimate) {
    final details = estimate.fallCleanup!;
    final currency = PdfLayoutHelpers.currency;
    return [
      _cardRow(
        title: 'Cleanup Package',
        hint: 'Choose one',
        options: FallCleanupCatalog.packages,
        prices: details.packagePrices,
        selectedKey: details.selection.package,
      ),
      pw.SizedBox(height: 16),
      _cardRow(
        title: 'Leaf Removal & Disposal',
        hint: 'Choose one',
        options: FallCleanupCatalog.disposals,
        prices: details.disposalPrices,
        selectedKey: details.selection.disposal,
        zeroIsIncluded: true,
      ),
      pw.SizedBox(height: 16),
      _extrasTable(details),
      if (estimate.services.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        _sectionHeading('Additional Work', ''),
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
      ],
      pw.SizedBox(height: 14),
      _total(estimate, details),
    ];
  }
}
