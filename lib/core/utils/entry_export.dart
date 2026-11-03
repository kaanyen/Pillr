import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../../features/entries/domain/partnership_entry.dart';
import 'giving_ledger_pdf.dart';
import 'giving_ledger_report_models.dart';
import 'pdf_branding.dart';

/// Landscape Seline giving ledger PDF via system share sheet.
Future<void> shareEntriesPdf({
  required String title,
  required String subtitle,
  required List<PartnershipEntry> entries,
  required List<String> columnHeaders,
  String Function(num)? formatAmount,
  String filename = 'pillr-entries.pdf',
  String? logoUrl,
  String? generatedAtLine,
  String? exporterLine,
  String? footerBrand,
  String? organizationName,
  String? ministryYear,
  String? exporterName,
  String? currencySymbol,
  DateTime? generatedAt,
  String? Function(PartnershipEntry entry)? armNameOf,
}) async {
  final data = GivingLedgerReportBuilder.fromEntries(
    entries: entries,
    organizationName:
        organizationName ?? _organizationFromSubtitle(subtitle) ?? 'Church',
    periodScope: ministryYear,
    filterDescription: subtitle,
    reportTitle: title,
    generatedAtFormatted: generatedAtLine ?? '',
    exporterName: exporterName ?? _exporterFromLine(exporterLine) ?? '-',
    currencySymbol: currencySymbol ?? 'GHS',
    verificationSeed: generatedAt,
    armNameOf: armNameOf,
  );

  await shareGivingLedgerPdf(
    data: data,
    logoUrl: logoUrl,
    filename: filename,
  );
}

String? _organizationFromSubtitle(String subtitle) {
  final parts = subtitle.split(' · ');
  return parts.isNotEmpty ? parts.first.trim() : subtitle;
}

String? _exporterFromLine(String? line) {
  if (line == null || line.isEmpty) return null;
  const prefix = 'Exporter: ';
  if (line.startsWith(prefix)) return line.substring(prefix.length).trim();
  return line;
}

/// CSV for spreadsheet import.
String entriesToCsv(List<PartnershipEntry> entries) {
  final b = StringBuffer();
  b.writeln(
    'dateGiven,partnerName,memberId,fellowship,arm,period,amountCedis,status,submittedBy,approvedBy,createdAt',
  );
  for (final e in entries) {
    b.writeln(
      [
        _csv(pdfFormatDate(e.dateGiven)),
        _csv(e.partnerSnapshot['fullName']?.toString() ?? ''),
        _csv(e.partnerSnapshot['memberId']?.toString() ?? ''),
        _csv(e.partnerSnapshot['fellowship']?.toString() ?? ''),
        _csv(e.armSnapshot['name']?.toString() ?? ''),
        _csv(e.periodSnapshot['name']?.toString() ?? ''),
        e.amountCedis.toString(),
        e.status,
        _csv(pdfPersonName(e.createdBySnapshot)),
        _csv(
          e.status == 'approved'
              ? pdfPersonName(e.reviewedBySnapshot)
              : '',
        ),
        _timestamp(e.createdAt),
      ].join(','),
    );
  }
  return b.toString();
}

String _timestamp(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String _csv(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

Future<void> shareEntriesCsv(
  String csv, {
  required String filename,
  String? subject,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(csv));
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'text/csv', name: filename)],
      fileNameOverrides: [filename],
      subject: subject,
      downloadFallbackEnabled: true,
    ),
  );
}
