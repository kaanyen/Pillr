import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_branding.dart';

/// Generic table PDF for leaderboard, pending queue, activity exports (§16.4.1).
Future<void> shareTablePdf({
  required String title,
  required String subtitle,
  required List<String> headers,
  required List<List<String>> rows,
  String filename = 'pillr-report.pdf',
  String? logoUrl,
  String? generatedAtLine,
  String? exporterLine,
  String? footerBrand,
}) async {
  final doc = pw.Document();
  final logo = await resolvePdfLogo(logoUrl);
  final whenLine = generatedAtLine ?? DateTime.now().toIso8601String();
  doc.addPage(
    pw.MultiPage(
      footer: (ctx) => pdfFooterMeta(
            generatedAtLine: whenLine,
            exporterLine: exporterLine,
            brandLine: footerBrand,
          ),
      build: (ctx) => [
        ...pdfHeaderWidgets(logo: logo, title: title, subtitle: subtitle),
        if (rows.isEmpty)
          pw.Text('No rows.', style: const pw.TextStyle(fontSize: 11))
        else
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
      ],
    ),
  );
  final bytes = await doc.save();
  await Printing.sharePdf(bytes: bytes, filename: filename);
}
