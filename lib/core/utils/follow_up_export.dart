import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_branding.dart';
import 'pdf_style.dart';

/// One partner on the Follow up list, as the files show them.
class FollowUpRow {
  const FollowUpRow({
    required this.name,
    required this.memberId,
    required this.fellowship,
    required this.phones,
    required this.lastGave,
    required this.reason,
  });

  final String name;
  final String memberId;
  final String fellowship;
  final List<String> phones;
  final DateTime? lastGave;
  final String reason;
}

/// Who the list is for and who made it, said on both files.
class FollowUpHeader {
  const FollowUpHeader({
    required this.church,
    required this.window,
    required this.madeBy,
    required this.madeAt,
    this.logoUrl,
    this.markColorHex,
  });

  final String church;

  /// "60 days", "90 days", "6 months".
  final String window;
  final String madeBy;
  final DateTime madeAt;
  final String? logoUrl;
  final String? markColorHex;
}

String _last(DateTime? d) => d == null ? 'Not yet' : DateFormat('d MMM y').format(d);

String _since(DateTime? d, DateTime now) =>
    d == null ? '' : '${now.difference(d).inDays}';

/// The CSV: one partner per row, every phone number, ready for a spreadsheet
/// or a bulk SMS tool.
String followUpCsv(List<FollowUpRow> rows, {DateTime? now}) {
  final at = now ?? DateTime.now();
  String c(String s) =>
      RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  final out = StringBuffer(
    'Partner,Member ID,Fellowship,Phone,Other phones,Last gave,Days since,Reason\r\n',
  );
  for (final r in rows) {
    out.write([
      r.name,
      r.memberId,
      r.fellowship,
      r.phones.isEmpty ? '' : r.phones.first,
      r.phones.skip(1).join(' / '),
      r.lastGave == null ? 'Not yet' : DateFormat('yyyy-MM-dd').format(r.lastGave!),
      _since(r.lastGave, at),
      r.reason,
    ].map(c).join(','));
    out.write('\r\n');
  }
  return out.toString();
}

/// The PDF, in the giving report's look (canvas 49): the church's mark and
/// name, what the list is, three figures, then every partner, longest quiet
/// first. Later pages repeat the church, the title and the column heads.
Future<List<int>> buildFollowUpPdfBytes(List<FollowUpRow> rows, FollowUpHeader h) async {
  final f = await loadPdfFonts();
  final logo = (h.logoUrl == null || h.logoUrl!.isEmpty) ? null : await resolvePdfLogo(h.logoUrl);
  final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold);
  final title = "Partners who haven't given in ${h.window}";
  final made = DateFormat('d MMM y, HH:mm').format(h.madeAt);
  final doc = pw.Document(theme: theme, title: title, author: h.church, creator: 'Pillr');

  pw.Widget mark(double size) => pdfChurchMark(
    name: h.church,
    colorHex: h.markColorHex,
    logo: logo,
    fonts: f,
    size: size,
  );

  final never = rows.where((r) => r.lastGave == null).length;
  final withPhone = rows.where((r) => r.phones.isNotEmpty).length;
  final withReason = rows.where((r) => r.reason.trim().isNotEmpty).length;

  pw.Widget fig(String value, String label) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: pw.BoxDecoration(
        color: PdfInk.tint,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(value, style: pw.TextStyle(font: f.extraBold, fontSize: 16, color: PdfInk.navy)),
          pw.SizedBox(height: 1),
          pw.Text(label, style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: PdfInk.muted)),
        ],
      ),
    ),
  );

  final head = pw.TextStyle(font: f.medium, fontSize: 7.5, color: PdfInk.muted);
  final cell = pw.TextStyle(font: f.regular, fontSize: 8.6, color: PdfInk.text);
  final name = pw.TextStyle(font: f.medium, fontSize: 8.6, color: PdfInk.strong);
  final mono = pw.TextStyle(font: f.regular, fontSize: 7.8, color: PdfInk.muted, letterSpacing: 0.2);
  pw.Widget pad(pw.Widget child, {bool right = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5.2),
    child: right ? pw.Align(alignment: pw.Alignment.centerRight, child: child) : child,
  );

  final table = rows.isEmpty
      ? pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 18),
          child: pw.Text('Everyone has given recently. Nobody needs a call right now.', style: cell),
        )
      : pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(22),
            1: pw.FlexColumnWidth(2.3),
            2: pw.FlexColumnWidth(1.1),
            3: pw.FlexColumnWidth(1.3),
            4: pw.FlexColumnWidth(1.6),
            5: pw.FlexColumnWidth(1.2),
            6: pw.FlexColumnWidth(2.0),
          },
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfInk.rule, width: 0.6),
            bottom: pw.BorderSide(color: PdfInk.rule, width: 0.6),
          ),
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfInk.head, width: 0.8)),
              ),
              children: [
                pad(pw.Text('#', style: head)),
                pad(pw.Text('Partner', style: head)),
                pad(pw.Text('Member ID', style: head)),
                pad(pw.Text('Fellowship', style: head)),
                pad(pw.Text('Phone', style: head)),
                pad(pw.Text('Last gave', style: head)),
                pad(pw.Text('Reason', style: head)),
              ],
            ),
            for (final (i, r) in rows.indexed)
              pw.TableRow(
                children: [
                  pad(pw.Text('${i + 1}', style: mono)),
                  pad(pw.Text(pdfSafeText(r.name), style: name)),
                  pad(pw.Text(r.memberId.isEmpty ? '-' : pdfSafeText(r.memberId), style: mono)),
                  pad(pw.Text(r.fellowship.isEmpty ? '-' : pdfSafeText(r.fellowship), style: cell)),
                  pad(pw.Text(r.phones.isEmpty ? '-' : pdfSafeText(r.phones.join('\n')), style: cell)),
                  pad(pw.Text(_last(r.lastGave), style: cell)),
                  pad(pw.Text(r.reason.trim().isEmpty ? '' : pdfSafeText(r.reason.trim()), style: cell)),
                ],
              ),
          ],
        );

  doc.addPage(
    pw.MultiPage(
      maxPages: 500,
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 27, 30, 22),
        theme: theme,
      ),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.only(bottom: 7),
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfInk.edge, width: 0.6)),
              ),
              child: pw.Row(
                children: [
                  mark(16),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Text(
                      '${pdfSafeText(h.church)} · $title',
                      style: pw.TextStyle(font: f.bold, fontSize: 8.2, color: PdfInk.navy),
                    ),
                  ),
                  pw.Text('Continued', style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: PdfInk.muted)),
                ],
              ),
            ),
      footer: (context) {
        final style = pw.TextStyle(font: f.regular, fontSize: 7.3, color: PdfInk.muted);
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.only(top: 7),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfInk.edge, width: 0.6)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Active partners with no approved giving since ${DateFormat('d MMM y').format(h.madeAt.subtract(_windowDuration(h.window)))}.',
                  style: style,
                ),
              ),
              pw.Text(
                'Made with Pillr by ${pdfSafeText(h.madeBy)} · $made · Page ${context.pageNumber} of ${context.pagesCount}',
                style: style,
              ),
            ],
          ),
        );
      },
      build: (context) => [
        pw.Row(
          children: [
            mark(26),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    pdfSafeText(h.church),
                    style: pw.TextStyle(font: f.extraBold, fontSize: 10.5, color: PdfInk.navy),
                  ),
                  pw.Text('Follow up', style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: PdfInk.muted)),
                ],
              ),
            ),
            pw.Text(
              'Made $made\nby ${pdfSafeText(h.madeBy)}',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: PdfInk.muted, lineSpacing: 1.5),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          title,
          style: pw.TextStyle(font: f.extraBold, fontSize: 19, color: PdfInk.navy, letterSpacing: -0.3),
        ),
        pw.SizedBox(height: 5),
        pw.Wrap(spacing: 4, children: [pdfChip('Longest quiet first', f), pdfChip('Active partners only', f)]),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            fig('${rows.length}', rows.length == 1 ? 'partner to call' : 'partners to call'),
            pw.SizedBox(width: 8),
            fig('$never', 'never given yet'),
            pw.SizedBox(width: 8),
            fig('$withPhone', 'with a phone number'),
            pw.SizedBox(width: 8),
            fig('$withReason', 'with a reason noted'),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('Every partner, longest quiet first', style: pdfLabel(f)),
        pw.SizedBox(height: 2),
        table,
      ],
    ),
  );
  return doc.save();
}

Duration _windowDuration(String window) {
  final m = RegExp(r'(\d+)\s*(day|month)').firstMatch(window);
  if (m == null) return Duration.zero;
  final n = int.parse(m.group(1)!);
  return Duration(days: m.group(2) == 'month' ? n * 30 : n);
}

/// Opens the phone's share sheet (Save to Files, Drive, WhatsApp, email);
/// on a computer, the file downloads.
Future<void> shareFollowUpPdf(List<FollowUpRow> rows, FollowUpHeader h, String filename) async {
  final bytes = await buildFollowUpPdfBytes(rows, h);
  await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: filename);
}

Future<void> shareFollowUpCsv(List<FollowUpRow> rows, FollowUpHeader h, String filename) async {
  final bytes = Uint8List.fromList(utf8.encode(followUpCsv(rows, now: h.madeAt)));
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'text/csv', name: filename)],
      fileNameOverrides: [filename],
      subject: '${h.church} — Follow up',
      downloadFallbackEnabled: true,
    ),
  );
}
