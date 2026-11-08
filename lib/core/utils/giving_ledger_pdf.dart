import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'giving_ledger_report_models.dart';
import 'pdf_branding.dart';

/// The app's colours, for paper.
abstract final class _Ink {
  static final navy = PdfColor.fromHex('#13426f');
  static final text = PdfColor.fromHex('#40444e');
  static final strong = PdfColor.fromHex('#212121');
  static final muted = PdfColor.fromHex('#616c8a');
  static final rule = PdfColor.fromHex('#edf1f5');
  static final head = PdfColor.fromHex('#d9e1ea');
  static final edge = PdfColor.fromHex('#e3e8ee');
  static final tint = PdfColor.fromHex('#eef6fe');
  static final track = PdfColor.fromHex('#edf1f5');
  static final barColours = [
    PdfColor.fromHex('#13426f'),
    PdfColor.fromHex('#2e96ff'),
    PdfColor.fromHex('#9acff6'),
    PdfColor.fromHex('#c9d4e0'),
  ];
}

class _Fonts {
  const _Fonts(this.regular, this.medium, this.bold, this.extraBold);

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;
  final pw.Font extraBold;
}

Future<_Fonts> _loadFonts() async {
  Future<pw.Font> load(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  return _Fonts(
    await load('Manrope-Regular'),
    await load('Manrope-SemiBold'),
    await load('Manrope-Bold'),
    await load('Manrope-ExtraBold'),
  );
}

String formatLedgerCurrency(num amount, {required String currencySymbol}) {
  final formatted = NumberFormat('#,##0.00').format(amount);
  final s = currencySymbol.trim();
  // A three-letter code reads better with a space: GHS 1,250.00, ₵1,250.00.
  return s.length > 1 ? '$s $formatted' : '$s$formatted';
}

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _statusLabel(String status) => switch (status) {
  'pending' => 'Waiting',
  'declined' => 'Sent back',
  _ => _capitalize(status),
};

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

/// The figures the first page leads with, worked out from the rows.
class _Summary {
  _Summary(GivingLedgerReportData data) {
    final rows = data.records;
    entries = rows.length;
    partners = {
      for (final r in rows) r.partnerId.isNotEmpty ? r.partnerId : r.partnerName,
    }.length;
    average = entries == 0 ? 0 : data.totalGivingsAmount / entries;
    final dated = [for (final r in rows) if (r.date != null) r];
    if (dated.isNotEmpty) {
      final dates = dated.map((r) => r.date!).toList()..sort();
      from = dates.first;
      to = dates.last;
      final byMonth = <int, double>{};
      for (final r in dated) {
        final k = r.date!.year * 12 + r.date!.month - 1;
        byMonth[k] = (byMonth[k] ?? 0) + r.amount;
      }
      final top = byMonth.entries.reduce((a, b) => a.value >= b.value ? a : b);
      biggestMonth = DateFormat('MMMM').format(DateTime(top.key ~/ 12, top.key % 12 + 1));
    }
    allApproved = rows.every((r) => r.status == 'approved');
  }

  late final int entries;
  late final int partners;
  late final double average;
  DateTime? from;
  DateTime? to;
  String? biggestMonth;
  late final bool allApproved;

  String? get range {
    if (from == null || to == null) return null;
    final f = DateFormat(from!.year == to!.year ? 'd MMM' : 'd MMM y').format(from!);
    return '$f to ${DateFormat('d MMM y').format(to!)}';
  }
}

/// Builds the giving report as landscape A4, as on the canvas (board 49):
/// the church and what the report covers, the total with entries, partners,
/// average entry and biggest month, each arm's share, then every entry,
/// newest first. Every following page repeats the church, the title and the
/// column heads; every page says only approved giving counts, who made it,
/// when, and a check code.
Future<List<int>> buildGivingLedgerPdfBytes(
  GivingLedgerReportData data, {
  String? logoUrl,
}) async {
  final fonts = await _loadFonts();
  final logo = (logoUrl == null || logoUrl.isEmpty) ? null : await resolvePdfLogo(logoUrl);
  final theme = pw.ThemeData.withFont(
    base: fonts.regular,
    bold: fonts.bold,
  );
  final doc = pw.Document(
    theme: theme,
    title: data.scopeLine,
    author: data.organizationName,
    creator: 'Pillr',
  );
  final summary = _Summary(data);

  doc.addPage(
    pw.MultiPage(
      maxPages: 500,
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(33, 27, 33, 22),
        theme: theme,
      ),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : _runningHead(data, logo, fonts),
      footer: (context) => _footer(context, data, fonts),
      build: (context) => [
        _masthead(data, logo, fonts),
        pw.SizedBox(height: 16),
        pw.Text(
          data.scopeLine,
          style: pw.TextStyle(font: fonts.extraBold, fontSize: 19, color: _Ink.navy, letterSpacing: -0.3),
        ),
        pw.SizedBox(height: 5),
        pw.Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (summary.range != null) _chip(summary.range!, fonts),
            _chip(summary.allApproved ? 'Approved only' : 'Includes entries not yet approved', fonts),
          ],
        ),
        pw.SizedBox(height: 14),
        _figures(data, summary, fonts),
        pw.SizedBox(height: 14),
        pw.Text('Every entry, newest first', style: _label(fonts)),
        pw.SizedBox(height: 2),
        _entries(data, fonts),
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
  await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: filename);
}

pw.TextStyle _label(_Fonts f) =>
    pw.TextStyle(font: f.medium, fontSize: 7.8, color: _Ink.muted);

pw.Widget _mark(GivingLedgerReportData data, pw.ImageProvider? logo, _Fonts f, double size) {
  if (logo != null) {
    return pw.ClipRRect(
      horizontalRadius: size * 0.28,
      verticalRadius: size * 0.28,
      child: pw.Image(logo, width: size, height: size, fit: pw.BoxFit.cover),
    );
  }
  return pw.Container(
    width: size,
    height: size,
    alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(
      color: data.markColorHex == null ? _Ink.navy : PdfColor.fromHex(data.markColorHex!),
      borderRadius: pw.BorderRadius.circular(size * 0.28),
    ),
    child: pw.Text(
      _initials(data.organizationName),
      style: pw.TextStyle(font: f.extraBold, fontSize: size * 0.36, color: PdfColors.white),
    ),
  );
}

pw.Widget _masthead(GivingLedgerReportData data, pw.ImageProvider? logo, _Fonts f) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      _mark(data, logo, f, 26),
      pw.SizedBox(width: 8),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              pdfSafeText(data.organizationName),
              style: pw.TextStyle(font: f.extraBold, fontSize: 10.5, color: _Ink.navy),
            ),
            pw.Text('Giving report', style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: _Ink.muted)),
          ],
        ),
      ),
      pw.Text(
        'Made ${pdfSafeText(data.generatedAtFormatted)}\nby ${pdfSafeText(data.exporterName)}',
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: _Ink.muted, lineSpacing: 1.5),
      ),
    ],
  );
}

pw.Widget _runningHead(GivingLedgerReportData data, pw.ImageProvider? logo, _Fonts f) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 8),
    padding: const pw.EdgeInsets.only(bottom: 7),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _Ink.edge, width: 0.6)),
    ),
    child: pw.Row(
      children: [
        _mark(data, logo, f, 16),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(
            '${pdfSafeText(data.organizationName)} · ${data.scopeLine}',
            style: pw.TextStyle(font: f.bold, fontSize: 8.2, color: _Ink.navy),
          ),
        ),
        pw.Text('Continued', style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: _Ink.muted)),
      ],
    ),
  );
}

pw.Widget _chip(String text, _Fonts f) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  decoration: pw.BoxDecoration(color: _Ink.tint, borderRadius: pw.BorderRadius.circular(8)),
  child: pw.Text(text, style: pw.TextStyle(font: f.medium, fontSize: 8, color: _Ink.navy)),
);

pw.Widget _figures(GivingLedgerReportData data, _Summary s, _Fonts f) {
  final total = formatLedgerCurrency(data.totalGivingsAmount, currencySymbol: data.currencySymbol);
  final dot = total.lastIndexOf('.');
  pw.Widget fig(String label, String value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: _label(f)),
      pw.Text(value, style: pw.TextStyle(font: f.extraBold, fontSize: 12, color: _Ink.navy)),
    ],
  );

  final box = pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(13, 12, 13, 12),
    decoration: pw.BoxDecoration(color: _Ink.tint, borderRadius: pw.BorderRadius.circular(10)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(s.allApproved ? 'Total approved' : 'Total', style: _label(f)),
        pw.RichText(
          text: pw.TextSpan(
            text: dot < 0 ? total : total.substring(0, dot),
            style: pw.TextStyle(font: f.extraBold, fontSize: 22, color: _Ink.navy),
            children: [
              if (dot >= 0)
                pw.TextSpan(
                  text: total.substring(dot),
                  style: pw.TextStyle(font: f.bold, fontSize: 12.5, color: _Ink.muted),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            pw.Expanded(child: fig('Entries', NumberFormat('#,##0').format(s.entries))),
            pw.Expanded(child: fig('Partners', NumberFormat('#,##0').format(s.partners))),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Row(
          children: [
            pw.Expanded(
              child: fig('Average entry', formatLedgerCurrency(s.average, currencySymbol: data.currencySymbol)),
            ),
            pw.Expanded(child: fig('Biggest month', s.biggestMonth ?? '-')),
          ],
        ),
      ],
    ),
  );

  final arms = data.armSummaries;
  final armTotal = arms.fold<double>(0, (a, b) => a + b.subtotalAmount);
  final byArm = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('By arm', style: _label(f)),
      pw.SizedBox(height: 2),
      if (arms.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text('No giving in this report.', style: pw.TextStyle(font: f.regular, fontSize: 8.5, color: _Ink.muted)),
        ),
      for (var i = 0; i < arms.length && i < 8; i++)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _Ink.rule, width: 0.6)),
          ),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 70,
                child: pw.Text(
                  pdfSafeText(arms[i].armCategory),
                  style: pw.TextStyle(font: f.medium, fontSize: 8.6, color: _Ink.strong),
                ),
              ),
              pw.Expanded(
                child: pw.Stack(
                  children: [
                    pw.Container(height: 6, decoration: pw.BoxDecoration(color: _Ink.track, borderRadius: pw.BorderRadius.circular(3))),
                    pw.LayoutBuilder(
                      builder: (context, c) => pw.Container(
                        height: 6,
                        width: armTotal == 0 ? 0 : (c!.maxWidth * arms[i].subtotalAmount / armTotal).clamp(2, c.maxWidth).toDouble(),
                        decoration: pw.BoxDecoration(
                          color: _Ink.barColours[i.clamp(0, _Ink.barColours.length - 1)],
                          borderRadius: pw.BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 9),
              pw.SizedBox(
                width: 84,
                child: pw.Text(
                  formatLedgerCurrency(arms[i].subtotalAmount, currencySymbol: data.currencySymbol),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(font: f.bold, fontSize: 8.6, color: _Ink.navy),
                ),
              ),
              pw.SizedBox(
                width: 32,
                child: pw.Text(
                  armTotal == 0 ? '' : '${(100 * arms[i].subtotalAmount / armTotal).round()}%',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(font: f.regular, fontSize: 8.6, color: _Ink.muted),
                ),
              ),
            ],
          ),
        ),
      if (arms.length > 8)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('and ${arms.length - 8} more arms', style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: _Ink.muted)),
        ),
    ],
  );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(flex: 11, child: box),
      pw.SizedBox(width: 14),
      pw.Expanded(flex: 15, child: byArm),
    ],
  );
}

pw.Widget _entries(GivingLedgerReportData data, _Fonts f) {
  final head = pw.TextStyle(font: f.medium, fontSize: 7.5, color: _Ink.muted);
  final cell = pw.TextStyle(font: f.regular, fontSize: 8.6, color: _Ink.text);
  final name = pw.TextStyle(font: f.medium, fontSize: 8.6, color: _Ink.strong);
  final mono = pw.TextStyle(font: f.regular, fontSize: 7.8, color: _Ink.muted, letterSpacing: 0.2);
  final amount = pw.TextStyle(font: f.bold, fontSize: 8.6, color: _Ink.navy);
  final year = DateTime.now().year;

  String when(PartnerGivingRecord r) => r.date == null
      ? pdfSafeText(r.dateGiven)
      : DateFormat(r.date!.year == year ? 'd MMM' : 'd MMM y').format(r.date!);

  if (data.records.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 18),
      child: pw.Text('No entries match this report.', style: cell),
    );
  }

  pw.Widget pad(pw.Widget child, {bool right = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5.2),
    child: right ? pw.Align(alignment: pw.Alignment.centerRight, child: child) : child,
  );

  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(1.0),
      1: pw.FlexColumnWidth(2.2),
      2: pw.FlexColumnWidth(1.3),
      3: pw.FlexColumnWidth(1.3),
      4: pw.FlexColumnWidth(1.3),
      5: pw.FlexColumnWidth(1.1),
      6: pw.FlexColumnWidth(1.4),
    },
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _Ink.rule, width: 0.6),
      bottom: pw.BorderSide(color: _Ink.rule, width: 0.6),
    ),
    children: [
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _Ink.head, width: 0.8)),
        ),
        children: [
          pad(pw.Text('Date given', style: head)),
          pad(pw.Text('Partner', style: head)),
          pad(pw.Text('Member ID', style: head)),
          pad(pw.Text('Fellowship', style: head)),
          pad(pw.Text('Arm', style: head)),
          pad(pw.Text('Status', style: head)),
          pad(pw.Text('Amount', style: head), right: true),
        ],
      ),
      for (final r in data.records)
        pw.TableRow(
          children: [
            pad(pw.Text(when(r), style: cell)),
            pad(pw.Text(pdfSafeText(r.partnerName), style: name)),
            pad(pw.Text(r.memberId.isEmpty ? '-' : pdfSafeText(r.memberId), style: mono)),
            pad(pw.Text(r.fellowship.isEmpty ? '-' : pdfSafeText(r.fellowship), style: cell)),
            pad(pw.Text(pdfSafeText(r.armCategory), style: cell)),
            pad(pw.Text(_statusLabel(r.status), style: cell)),
            pad(
              pw.Text(formatLedgerCurrency(r.amount, currencySymbol: data.currencySymbol), style: amount),
              right: true,
            ),
          ],
        ),
    ],
  );
}

pw.Widget _footer(pw.Context context, GivingLedgerReportData data, _Fonts f) {
  final style = pw.TextStyle(font: f.regular, fontSize: 7.3, color: _Ink.muted);
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    padding: const pw.EdgeInsets.only(top: 7),
    decoration: pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _Ink.edge, width: 0.6)),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            data.records.every((r) => r.status == 'approved')
                ? 'Approved giving only. Entries still waiting for a pastor are not counted.'
                : 'This report includes entries a pastor has not approved yet; check the Status column.',
            style: style,
          ),
        ),
        pw.RichText(
          text: pw.TextSpan(
            style: style,
            children: [
              pw.TextSpan(text: 'Made with Pillr by ${pdfSafeText(data.exporterName)} · ${pdfSafeText(data.generatedAtFormatted)} · Check code '),
              pw.TextSpan(
                text: pdfSafeText(data.verificationId),
                style: pw.TextStyle(font: f.bold, fontSize: 7.3, color: _Ink.navy),
              ),
              pw.TextSpan(text: ' · Page ${context.pageNumber} of ${context.pagesCount}'),
            ],
          ),
        ),
      ],
    ),
  );
}
