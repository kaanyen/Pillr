import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/entries/domain/partnership_entry.dart';
import 'currency_utils.dart';
import 'pdf_branding.dart';

/// Build doc §16.4.1 — client-side PDF via system share sheet.
Future<void> shareEntriesPdf({
  required String title,
  required String subtitle,
  required List<PartnershipEntry> entries,
  required List<String> columnHeaders,
  String filename = 'pillr-entries.pdf',
  String? logoUrl,
  String? generatedAtLine,
  String? exporterLine,
  String? footerBrand,
}) async {
  final doc = pw.Document();
  final logo = await resolvePdfLogo(logoUrl);
  final whenLine = generatedAtLine ?? DateTime.now().toIso8601String();
  final data = <List<String>>[
    for (final e in entries)
      [
        e.partnerSnapshot['fullName']?.toString() ?? '—',
        formatCedis(e.amountCedis),
        e.status,
        e.periodSnapshot['name']?.toString() ?? '—',
        e.armSnapshot['name']?.toString() ?? '—',
        '${e.dateGiven.year}-${e.dateGiven.month.toString().padLeft(2, '0')}-${e.dateGiven.day.toString().padLeft(2, '0')}',
      ],
  ];
  doc.addPage(
    pw.MultiPage(
      footer: (ctx) => pdfFooterMeta(
            generatedAtLine: whenLine,
            exporterLine: exporterLine,
            brandLine: footerBrand,
          ),
      build: (ctx) => [
        ...pdfHeaderWidgets(logo: logo, title: title, subtitle: subtitle),
        if (entries.isEmpty)
          pw.Text('No rows.', style: const pw.TextStyle(fontSize: 11))
        else
          pw.TableHelper.fromTextArray(
            headers: columnHeaders,
            data: data,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
            },
          ),
      ],
    ),
  );
  final bytes = await doc.save();
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

/// CSV for spreadsheet import.
String entriesToCsv(List<PartnershipEntry> entries) {
  final b = StringBuffer();
  b.writeln('partnerName,amountCedis,status,arm,period,dateGiven,createdAt');
  for (final e in entries) {
    b.writeln(
      [
        _csv(e.partnerSnapshot['fullName']?.toString() ?? ''),
        e.amountCedis.toString(),
        e.status,
        _csv(e.armSnapshot['name']?.toString() ?? ''),
        _csv(e.periodSnapshot['name']?.toString() ?? ''),
        e.dateGiven.toIso8601String(),
        e.createdAt.toIso8601String(),
      ].join(','),
    );
  }
  return b.toString();
}

String _csv(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

Future<void> shareEntriesCsv(String csv, {String subject = 'Pillr entries export'}) async {
  await SharePlus.instance.share(ShareParams(text: csv, subject: subject));
}
