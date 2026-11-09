import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_branding.dart';
import 'pdf_style.dart';

/// One approved entry on a statement or a receipt.
class StatementLine {
  const StatementLine({
    required this.date,
    required this.arm,
    required this.amount,
  });

  final DateTime date;
  final String arm;
  final double amount;
}

/// Everything a partner's giving statement shows.
class PartnerStatementData {
  const PartnerStatementData({
    required this.churchName,
    required this.partnerName,
    required this.memberId,
    required this.fellowship,
    required this.periodName,
    required this.periodStart,
    required this.periodEnd,
    required this.lines,
    required this.pastorName,
    required this.madeBy,
    required this.madeAt,
    required this.checkCode,
    this.currencySymbol = 'GHS',
    this.markColorHex,
  });

  final String churchName;
  final String partnerName;
  final String memberId;
  final String fellowship;
  final String periodName;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// Approved giving only, any order.
  final List<StatementLine> lines;
  final String pastorName;
  final String madeBy;
  final DateTime madeAt;
  final String checkCode;
  final String currencySymbol;
  final String? markColorHex;

  double get total => lines.fold(0, (s, l) => s + l.amount);
}

/// A partner's giving statement for a period, as on the canvas (board 51):
/// A4 portrait, their name and what they gave, by arm, month by month and
/// every entry, signed by the pastor.
Future<List<int>> buildPartnerStatementPdfBytes(
  PartnerStatementData d, {
  String? logoUrl,
}) async {
  final f = await loadPdfFonts();
  final logo = (logoUrl == null || logoUrl.isEmpty) ? null : await resolvePdfLogo(logoUrl);
  final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold);
  final doc = pw.Document(
    theme: theme,
    title: 'Giving statement · ${d.partnerName} · ${d.periodName}',
    author: d.churchName,
    creator: 'Pillr',
  );
  String money(num v) => formatLedgerCurrency(v, currencySymbol: d.currencySymbol);

  final lines = [...d.lines]..sort((a, b) => b.date.compareTo(a.date));
  final byArm = <String, double>{};
  final byMonth = <int, double>{};
  for (final l in lines) {
    byArm[l.arm] = (byArm[l.arm] ?? 0) + l.amount;
    final k = l.date.year * 12 + l.date.month - 1;
    byMonth[k] = (byMonth[k] ?? 0) + l.amount;
  }
  final arms = byArm.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final months = <int>[
    for (var k = d.periodStart.year * 12 + d.periodStart.month - 1;
        k <= d.periodEnd.year * 12 + d.periodEnd.month - 1 && k < d.periodStart.year * 12 + d.periodStart.month + 11;
        k++)
      k,
  ];
  final gaveIn = months.where((k) => (byMonth[k] ?? 0) > 0).length;
  final cell = pw.TextStyle(font: f.regular, fontSize: 9, color: PdfInk.text);
  final amountStyle = pw.TextStyle(font: f.bold, fontSize: 9, color: PdfInk.navy);
  final compact = NumberFormat('#,##0');

  pw.Widget row(String a, String b, {bool last = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
    decoration: last
        ? null
        : pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfInk.rule, width: 0.6))),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(a, style: pw.TextStyle(font: f.medium, fontSize: 9, color: PdfInk.strong))),
        pw.Text(b, style: amountStyle),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 36, 42, 28),
        theme: theme,
      ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.only(top: 7),
        decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfInk.edge, width: 0.6))),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Approved giving recorded by ${pdfSafeText(d.churchName)}. Keep this statement for your records.',
                style: pw.TextStyle(font: f.regular, fontSize: 7.2, color: PdfInk.muted),
              ),
            ),
            pw.RichText(
              text: pw.TextSpan(
                style: pw.TextStyle(font: f.regular, fontSize: 7.2, color: PdfInk.muted),
                children: [
                  const pw.TextSpan(text: 'Check code '),
                  pw.TextSpan(text: d.checkCode, style: pw.TextStyle(font: f.bold, fontSize: 7.2, color: PdfInk.navy)),
                  pw.TextSpan(text: ' · Page ${context.pageNumber} of ${context.pagesCount}'),
                ],
              ),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pdfChurchMark(name: d.churchName, fonts: f, size: 26, colorHex: d.markColorHex, logo: logo),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(pdfSafeText(d.churchName), style: pw.TextStyle(font: f.extraBold, fontSize: 10.5, color: PdfInk.navy)),
                  pw.Text('Giving statement', style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: PdfInk.muted)),
                ],
              ),
            ),
            pw.Text(
              'Made ${DateFormat('d MMM y').format(d.madeAt)}\nby ${pdfSafeText(d.madeBy)}',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: PdfInk.muted, lineSpacing: 1.5),
            ),
          ],
        ),
        pw.SizedBox(height: 22),
        pw.Text(pdfSafeText(d.partnerName), style: pw.TextStyle(font: f.extraBold, fontSize: 19, color: PdfInk.navy)),
        pw.SizedBox(height: 5),
        pw.Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (d.memberId.isNotEmpty) pdfChip(d.memberId, f),
            if (d.fellowship.isNotEmpty) pdfChip(pdfSafeText(d.fellowship), f),
            pdfChip(
              '${pdfSafeText(d.periodName)} · ${DateFormat('d MMM').format(d.periodStart)} to ${DateFormat('d MMM').format(d.periodEnd)}',
              f,
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 10,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(13),
                decoration: pw.BoxDecoration(color: PdfInk.tint, borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('You gave in ${pdfSafeText(d.periodName)}', style: pdfLabel(f)),
                    pdfBigMoney(money(d.total), f),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      '${lines.length} ${lines.length == 1 ? 'entry' : 'entries'} in $gaveIn ${gaveIn == 1 ? 'month' : 'months'} · approved by the church',
                      style: pw.TextStyle(font: f.regular, fontSize: 8, color: PdfInk.muted),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              flex: 12,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('By arm', style: pdfLabel(f)),
                  if (arms.isEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 6),
                      child: pw.Text('No approved giving in this period.', style: cell),
                    ),
                  for (var i = 0; i < arms.length; i++)
                    row(pdfSafeText(arms[i].key), money(arms[i].value), last: i == arms.length - 1),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Text('Month by month', style: pdfLabel(f)),
        pw.SizedBox(height: 4),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfInk.rule, width: 0.6),
            borderRadius: pw.BorderRadius.circular(7),
          ),
          child: pw.Row(
            children: [
              for (var i = 0; i < months.length; i++)
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 5),
                    decoration: i == months.length - 1
                        ? null
                        : pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfInk.rule, width: 0.6))),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          DateFormat('MMM').format(DateTime(months[i] ~/ 12, months[i] % 12 + 1)),
                          style: pdfLabel(f),
                        ),
                        pw.Text(
                          (byMonth[months[i]] ?? 0) > 0 ? compact.format(byMonth[months[i]]) : '-',
                          style: pw.TextStyle(
                            font: f.bold,
                            fontSize: 8,
                            color: (byMonth[months[i]] ?? 0) > 0 ? PdfInk.navy : PdfInk.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 15),
        pw.Text('Every entry', style: pdfLabel(f)),
        pw.SizedBox(height: 2),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1.2),
          },
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfInk.rule, width: 0.6)),
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfInk.head, width: 0.8))),
              children: [
                for (final (h, right) in const [('Date given', false), ('Arm', false), ('Amount', true)])
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: pw.Text(h, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: pdfLabel(f)),
                  ),
              ],
            ),
            for (final l in lines)
              pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(pdfShortDate(l.date), style: cell)),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(pdfSafeText(l.arm), style: cell)),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(money(l.amount), textAlign: pw.TextAlign.right, style: amountStyle),
                  ),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text('With gratitude,', style: pw.TextStyle(font: f.regular, fontSize: 9.5, color: PdfInk.text)),
        if (d.pastorName.trim().isNotEmpty)
          pw.Text(pdfSafeText(d.pastorName), style: pw.TextStyle(font: f.bold, fontSize: 9.5, color: PdfInk.navy)),
        pw.Text(pdfSafeText(d.churchName), style: pw.TextStyle(font: f.regular, fontSize: 8, color: PdfInk.muted)),
      ],
    ),
  );
  return doc.save();
}

Future<void> sharePartnerStatementPdf(
  PartnerStatementData data, {
  String? logoUrl,
  required String filename,
}) async {
  final bytes = await buildPartnerStatementPdfBytes(data, logoUrl: logoUrl);
  await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: filename);
}

/// One approved entry's receipt.
class EntryReceiptData {
  const EntryReceiptData({
    required this.churchName,
    required this.partnerName,
    required this.memberId,
    required this.fellowship,
    required this.amount,
    required this.arm,
    required this.dateGiven,
    required this.periodName,
    required this.approvedAt,
    required this.approvedBy,
    required this.recordedBy,
    required this.receiptNumber,
    required this.pastorName,
    required this.madeAt,
    this.note,
    this.currencySymbol = 'GHS',
    this.markColorHex,
  });

  final String churchName;
  final String partnerName;
  final String memberId;
  final String fellowship;
  final double amount;
  final String arm;
  final DateTime dateGiven;
  final String periodName;
  final DateTime? approvedAt;
  final String approvedBy;
  final String recordedBy;
  final String receiptNumber;
  final String pastorName;
  final DateTime madeAt;
  final String? note;
  final String currencySymbol;
  final String? markColorHex;
}

/// A receipt for one approved entry, as on the canvas (board 52): A5, the
/// partner and the amount up top, then what it was toward and who approved
/// it, and a receipt number.
Future<List<int>> buildEntryReceiptPdfBytes(
  EntryReceiptData d, {
  String? logoUrl,
}) async {
  final f = await loadPdfFonts();
  final logo = (logoUrl == null || logoUrl.isEmpty) ? null : await resolvePdfLogo(logoUrl);
  final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold);
  final doc = pw.Document(
    theme: theme,
    title: 'Receipt ${d.receiptNumber}',
    author: d.churchName,
    creator: 'Pillr',
  );
  pw.Widget kv(String k, String v, {bool mono = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 7),
    decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfInk.rule, width: 0.6))),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(k, style: pw.TextStyle(font: f.regular, fontSize: 9.5, color: PdfInk.muted)),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Text(
            v,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              font: mono ? f.bold : f.medium,
              fontSize: 9.5,
              color: PdfInk.strong,
              letterSpacing: mono ? 0.6 : 0,
            ),
          ),
        ),
      ],
    ),
  );

  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 22),
        theme: theme,
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            children: [
              pdfChurchMark(name: d.churchName, fonts: f, size: 26, colorHex: d.markColorHex, logo: logo),
              pw.SizedBox(width: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(pdfSafeText(d.churchName), style: pw.TextStyle(font: f.extraBold, fontSize: 10.5, color: PdfInk.navy)),
                  pw.Text('Receipt for giving', style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: PdfInk.muted)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: pw.BoxDecoration(color: PdfInk.tint, borderRadius: pw.BorderRadius.circular(12)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Received with thanks from', style: pdfLabel(f)),
                pw.Text(pdfSafeText(d.partnerName), style: pw.TextStyle(font: f.extraBold, fontSize: 15, color: PdfInk.navy)),
                pw.Text(
                  [d.memberId, d.fellowship].where((s) => s.isNotEmpty).map(pdfSafeText).join(' · '),
                  style: pw.TextStyle(font: f.regular, fontSize: 8, color: PdfInk.muted),
                ),
                pw.SizedBox(height: 10),
                pdfBigMoney(formatLedgerCurrency(d.amount, currencySymbol: d.currencySymbol), f, size: 26),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          kv('Toward', pdfSafeText(d.arm)),
          kv('Given on', DateFormat('d MMMM y').format(d.dateGiven)),
          kv('Period', pdfSafeText(d.periodName)),
          kv(
            'Approved',
            d.approvedAt == null
                ? pdfSafeText(d.approvedBy)
                : '${DateFormat('d MMM y').format(d.approvedAt!)} by ${pdfSafeText(d.approvedBy)}',
          ),
          kv('Recorded by', pdfSafeText(d.recordedBy)),
          if ((d.note ?? '').trim().isNotEmpty) kv('Note', pdfSafeText(d.note!.trim())),
          kv('Receipt number', d.receiptNumber, mono: true),
          pw.SizedBox(height: 16),
          pw.Text(
            'Thank you for your giving. It is counted toward the work you gave it for.',
            style: pw.TextStyle(font: f.regular, fontSize: 9.5, color: PdfInk.text, lineSpacing: 2),
          ),
          pw.SizedBox(height: 10),
          if (d.pastorName.trim().isNotEmpty)
            pw.Text(pdfSafeText(d.pastorName), style: pw.TextStyle(font: f.bold, fontSize: 9.5, color: PdfInk.navy)),
          pw.Text(pdfSafeText(d.churchName), style: pw.TextStyle(font: f.regular, fontSize: 8, color: PdfInk.muted)),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 7),
            decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfInk.edge, width: 0.6))),
            child: pw.Text(
              'Made ${DateFormat('d MMM y').format(d.madeAt)} with Pillr. Only approved giving gets a receipt.',
              style: pw.TextStyle(font: f.regular, fontSize: 7.2, color: PdfInk.muted),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

Future<void> shareEntryReceiptPdf(
  EntryReceiptData data, {
  String? logoUrl,
  required String filename,
}) async {
  final bytes = await buildEntryReceiptPdfBytes(data, logoUrl: logoUrl);
  await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: filename);
}

/// A short, stable code from an entry's id: R-8F2K-61QA. The same entry
/// always gets the same receipt number.
String receiptNumberFor(String entryId) {
  final clean = entryId.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final padded = clean.padRight(8, '0');
  return 'R-${padded.substring(0, 4)}-${padded.substring(padded.length - 4)}';
}
