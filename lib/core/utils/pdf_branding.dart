import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The church's logo from its URL, else the Pillr mark.
Future<pw.ImageProvider> resolvePdfLogo(String? logoUrl) async {
  final fromUrl = await _loadPdfLogoFromUrl(logoUrl);
  if (fromUrl != null) return fromUrl;
  for (final asset in ['assets/branding/app_icon.png']) {
    try {
      final data = await rootBundle.load(asset);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      continue;
    }
  }
  throw StateError('No bundled Pillr logo asset found');
}

Future<pw.ImageProvider?> _loadPdfLogoFromUrl(String? url) async {
  if (url == null || url.isEmpty) return null;
  try {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) return null;
    return pw.MemoryImage(r.bodyBytes);
  } catch (_) {
    return null;
  }
}

List<pw.Widget> pdfHeaderWidgets({
  required pw.ImageProvider logo,
  required String title,
  required String subtitle,
}) {
  return [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          height: 44,
          width: 120,
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(logo, fit: pw.BoxFit.contain),
        ),
        pw.Spacer(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              subtitle,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 12),
    pw.Divider(color: PdfColors.grey400, thickness: 0.75),
    pw.SizedBox(height: 12),
  ];
}

/// Branded data table — §11 giving records layout.
pw.Widget pdfBrandedTable({
  required List<String> headers,
  required List<List<String>> rows,
  List<pw.Alignment>? columnAlignments,
}) {
  if (rows.isEmpty) {
    return pw.Text('No rows.', style: const pw.TextStyle(fontSize: 11));
  }

  final aligns = columnAlignments ??
      [
        for (var i = 0; i < headers.length; i++)
          i == headers.length - 2 ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      ];

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    columnWidths: {
      for (var i = 0; i < headers.length; i++)
        i: i == 0
            ? const pw.FlexColumnWidth(2.2)
            : i == headers.length - 2
                ? const pw.FixedColumnWidth(56)
                : const pw.FlexColumnWidth(),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (final header in headers)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Text(
                header,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey900,
                ),
              ),
            ),
        ],
      ),
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: rowIndex.isOdd ? PdfColors.grey100 : PdfColors.white,
          ),
          children: [
            for (var i = 0; i < rows[rowIndex].length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: pw.Align(
                  alignment: i < aligns.length ? aligns[i] : pw.Alignment.centerLeft,
                  child: pw.Text(
                    rows[rowIndex][i],
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey900),
                  ),
                ),
              ),
          ],
        ),
    ],
  );
}

/// Footer metadata for exports (build doc §11 — subtle branding).
pw.Widget pdfFooterMeta({
  required String generatedAtLine,
  String? exporterLine,
  String? brandLine,
}) {
  return pw.Container(
    alignment: pw.Alignment.centerLeft,
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Text(generatedAtLine, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        if (exporterLine != null && exporterLine.isNotEmpty)
          pw.Text(exporterLine, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        if (brandLine != null && brandLine.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              brandLine,
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey500,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
      ],
    ),
  );
}

String pdfFormatDate(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// Strips Unicode punctuation Helvetica cannot render in PDF exports.
String pdfSafeText(String? value, {String fallback = '-'}) {
  final raw =
      value == null || value.trim().isEmpty ? fallback : value.trim();
  return raw
      .replaceAll('\u2014', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2022', '|')
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'");
}

String pdfPersonName(Map<String, dynamic>? snapshot) =>
    pdfSafeText(snapshot?['fullName']?.toString());
