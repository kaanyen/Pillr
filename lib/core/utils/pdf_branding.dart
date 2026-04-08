import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Church logo from URL, or bundled app icon when missing or invalid.
Future<pw.ImageProvider> resolvePdfLogo(String? logoUrl) async {
  final fromUrl = await _loadPdfLogoFromUrl(logoUrl);
  if (fromUrl != null) return fromUrl;
  final data = await rootBundle.load('assets/branding/app_icon.png');
  return pw.MemoryImage(data.buffer.asUint8List());
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
    pw.Container(
      height: 44,
      alignment: pw.Alignment.centerLeft,
      child: pw.Image(logo, fit: pw.BoxFit.contain),
    ),
    pw.SizedBox(height: 8),
    pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 4),
    pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
    pw.SizedBox(height: 16),
  ];
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
          pw.Text(brandLine, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    ),
  );
}
