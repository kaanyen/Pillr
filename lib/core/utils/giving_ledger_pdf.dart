import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'giving_ledger_report_models.dart';
import 'pdf_branding.dart';

/// Print-friendly Seline tokens for the landscape giving report PDF.
abstract final class _PdfSel {
  static final white = PdfColor.fromHex('#ffffff');
  static final border = PdfColor.fromHex('#e8e6e5');
  static final ink = PdfColor.fromHex('#0c0a09');
  static final warm = PdfColor.fromHex('#78716c');
  static final cyanText = PdfColor.fromHex('#3398e1');
  static final cyanWash = PdfColor.fromHex('#c1e1f7');
}

class _PdfFonts {
  const _PdfFonts({
    required this.body,
    required this.bodyMedium,
    required this.display,
  });

  final pw.Font body;
  final pw.Font bodyMedium;
  final pw.Font display;
}

Future<_PdfFonts> _loadFonts() async {
  Future<pw.Font> load(String asset) async {
    final data = await rootBundle.load(asset);
    return pw.Font.ttf(data);
  }

  return _PdfFonts(
    body: await load('assets/fonts/Inter-Regular.ttf'),
    bodyMedium: await load('assets/fonts/Inter-Medium.ttf'),
    display: await load('assets/fonts/InterTight-Medium.ttf'),
  );
}

pw.TextStyle _bodyStyle(_PdfFonts fonts, {double size = 9}) {
  return pw.TextStyle(font: fonts.body, fontSize: size, color: _PdfSel.ink);
}

pw.TextStyle _mutedStyle(_PdfFonts fonts, {double size = 9}) {
  return pw.TextStyle(font: fonts.body, fontSize: size, color: _PdfSel.warm);
}

pw.TextStyle _headStyle(_PdfFonts fonts) {
  return pw.TextStyle(
    font: fonts.bodyMedium,
    fontSize: 7.5,
    color: _PdfSel.warm,
    letterSpacing: 0.4,
  );
}

String formatLedgerCurrency(num amount, {required String currencySymbol}) {
  final formatted = NumberFormat('#,##0.00').format(amount);
  return '$currencySymbol $formatted';
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

/// Builds landscape A4 PDF bytes for the Seline-styled giving report.
Future<List<int>> buildGivingLedgerPdfBytes(
  GivingLedgerReportData data, {
  String? logoUrl,
}) async {
  final fonts = await _loadFonts();
  final logo = await resolvePdfLogo(logoUrl);
  final theme = pw.ThemeData.withFont(base: fonts.body, bold: fonts.bodyMedium);
  final doc = pw.Document(theme: theme);

  doc.addPage(
    pw.MultiPage(
      maxPages: 500,
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        theme: theme,
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _PdfSel.white),
        ),
      ),
      footer: (context) => _reportFooter(context, data, fonts),
      build: (context) => [
        _headerBar(data, logo, fonts),
        pw.SizedBox(height: 16),
        _scopeTitle(data, fonts),
        pw.SizedBox(height: 14),
        _summaryRow(data, fonts),
        pw.SizedBox(height: 14),
        _givingTable(data, fonts),
      ],
    ),
  );

  return doc.save();
}

Future<void> shareGivingLedgerPdf({
  required GivingLedgerReportData data,
  String? logoUrl,
  required String filename,
}) async {
  final bytes = await buildGivingLedgerPdfBytes(data, logoUrl: logoUrl);
  await Printing.sharePdf(
    bytes: Uint8List.fromList(bytes),
    filename: filename,
  );
}

pw.Widget _headerBar(
  GivingLedgerReportData data,
  pw.ImageProvider logo,
  _PdfFonts fonts,
) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          height: 44,
          width: 120,
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(logo, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Text(
            pdfSafeText(data.organizationName),
            style: pw.TextStyle(
              font: fonts.display,
              fontSize: 12,
              color: _PdfSel.ink,
            ),
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: pw.Text(
            'Official Financial Document',
            style: _mutedStyle(fonts, size: 8),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _scopeTitle(GivingLedgerReportData data, _PdfFonts fonts) {
  final line = pdfSafeText(data.scopeLine);
  final highlight = pdfSafeText(data.scopeHighlight);
  final before = line.contains(highlight)
      ? line.substring(0, line.indexOf(highlight)).trimRight()
      : line;
  final after = line.contains(highlight)
      ? line.substring(line.indexOf(highlight) + highlight.length).trimLeft()
      : '';

  return pw.Wrap(
    crossAxisAlignment: pw.WrapCrossAlignment.center,
    spacing: 6,
    runSpacing: 4,
    children: [
      if (before.isNotEmpty)
        pw.Text(
          before.endsWith('·') ? before : '$before ·',
          style: pw.TextStyle(
            font: fonts.display,
            fontSize: 20,
            color: _PdfSel.ink,
            letterSpacing: -0.4,
          ),
        ),
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(7, 2, 7, 2),
        decoration: pw.BoxDecoration(
          color: _PdfSel.cyanWash,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          highlight,
          style: pw.TextStyle(
            font: fonts.display,
            fontSize: 20,
            color: _PdfSel.cyanText,
            letterSpacing: -0.4,
          ),
        ),
      ),
      if (after.isNotEmpty)
        pw.Text(
          after.startsWith('·') ? after.substring(1).trimLeft() : after,
          style: pw.TextStyle(
            font: fonts.display,
            fontSize: 20,
            color: _PdfSel.ink,
            letterSpacing: -0.4,
          ),
        ),
    ],
  );
}

pw.Widget _summaryRow(GivingLedgerReportData data, _PdfFonts fonts) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 4,
        child: pw.Container(
          padding: const pw.EdgeInsets.all(16),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'TOTAL GIVINGS',
                style: pw.TextStyle(
                  font: fonts.bodyMedium,
                  fontSize: 9,
                  color: _PdfSel.warm,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                formatLedgerCurrency(
                  data.totalGivingsAmount,
                  currencySymbol: data.currencySymbol,
                ),
                style: pw.TextStyle(
                  font: fonts.display,
                  fontSize: 24,
                  color: _PdfSel.ink,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Expanded(
        flex: 6,
        child: pw.Container(
          child: _armSummaryTable(data, fonts),
        ),
      ),
    ],
  );
}

pw.Widget _armSummaryTable(GivingLedgerReportData data, _PdfFonts fonts) {
  if (data.armSummaries.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(14),
      child: pw.Text('No arm categories.', style: _mutedStyle(fonts)),
    );
  }

  return pw.TableHelper.fromTextArray(
    headers: [
      'Arm Category',
      'Subtotal (${data.currencySymbol})',
    ],
    data: [
      for (final arm in data.armSummaries)
        [
          pdfSafeText(arm.armCategory),
          formatLedgerCurrency(
            arm.subtotalAmount,
            currencySymbol: data.currencySymbol,
          ),
        ],
    ],
    headerStyle: _headStyle(fonts),
    cellStyle: _bodyStyle(fonts),
    headerDecoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: _PdfSel.border, width: 0.5),
      ),
    ),
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _PdfSel.border, width: 0.5),
    ),
    columnWidths: {
      0: const pw.FlexColumnWidth(3),
      1: const pw.FlexColumnWidth(2),
    },
    headerAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerRight,
    },
    cellAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerRight,
    },
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  );
}

pw.Widget _givingTable(GivingLedgerReportData data, _PdfFonts fonts) {
  final rows = data.records.isEmpty
      ? const [
          ['-', '-', '-', '-', '-'],
        ]
      : [
          for (final row in data.records)
            [
              pdfSafeText(row.partnerName),
              pdfSafeText(row.armCategory),
              pdfSafeText(_capitalize(row.status)),
              pdfSafeText(row.dateGiven),
              formatLedgerCurrency(
                row.amount,
                currencySymbol: data.currencySymbol,
              ),
            ],
        ];

  return pw.TableHelper.fromTextArray(
      headers: [
        'Partner Name',
        'Arm Category',
        'Status',
        'Date Given',
        'Amount (${data.currencySymbol})',
      ],
      data: rows,
      headerStyle: _headStyle(fonts),
      cellStyle: _bodyStyle(fonts),
      headerDecoration: pw.BoxDecoration(
        color: _PdfSel.white,
        border: pw.Border(
          bottom: pw.BorderSide(color: _PdfSel.border, width: 0.5),
        ),
      ),
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _PdfSel.border, width: 0.5),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.4),
        1: const pw.FlexColumnWidth(1.6),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.4),
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerRight,
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerRight,
      },
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyleBuilder: (index, cell, rowNum) {
        if (index == 2 || index == 3) return _mutedStyle(fonts);
        return _bodyStyle(fonts);
      },
    );
}

pw.Widget _reportFooter(
  pw.Context context,
  GivingLedgerReportData data,
  _PdfFonts fonts,
) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    padding: const pw.EdgeInsets.only(top: 8),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            'Generated: ${pdfSafeText(data.generatedAtFormatted)}  |  '
            'Exporter: ${pdfSafeText(data.exporterName)}  |  '
            'Verification ID: ${pdfSafeText(data.verificationId)}',
            style: _mutedStyle(fonts, size: 7.5),
          ),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: _mutedStyle(fonts, size: 7.5),
        ),
      ],
    ),
  );
}
