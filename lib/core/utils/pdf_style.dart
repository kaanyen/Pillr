import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// What every Pillr PDF shares: the app's colours for paper, Manrope, money
/// written the same way, and the church's mark.

/// The app's colours, for paper.
abstract final class PdfInk {
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

class PdfFonts {
  const PdfFonts(this.regular, this.medium, this.bold, this.extraBold);

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;
  final pw.Font extraBold;
}

Future<PdfFonts> loadPdfFonts() async {
  Future<pw.Font> load(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  return PdfFonts(
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


/// Up to two initials from a name, for the church's mark.
String selPdfInitials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

/// The church's logo, or its initials on its mark colour (navy when it has
/// none).
pw.Widget pdfChurchMark({
  required String name,
  required PdfFonts fonts,
  required double size,
  String? colorHex,
  pw.ImageProvider? logo,
}) {
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
      color: colorHex == null ? PdfInk.navy : PdfColor.fromHex(colorHex),
      borderRadius: pw.BorderRadius.circular(size * 0.28),
    ),
    child: pw.Text(
      selPdfInitials(name),
      style: pw.TextStyle(font: fonts.extraBold, fontSize: size * 0.36, color: PdfColors.white),
    ),
  );
}

/// A big amount with its pesewas set small and grey: ₵1,250.00.
pw.Widget pdfBigMoney(String formatted, PdfFonts f, {double size = 22}) {
  final dot = formatted.lastIndexOf('.');
  return pw.RichText(
    text: pw.TextSpan(
      text: dot < 0 ? formatted : formatted.substring(0, dot),
      style: pw.TextStyle(font: f.extraBold, fontSize: size, color: PdfInk.navy),
      children: [
        if (dot >= 0)
          pw.TextSpan(
            text: formatted.substring(dot),
            style: pw.TextStyle(font: f.bold, fontSize: size * 0.57, color: PdfInk.muted),
          ),
      ],
    ),
  );
}

/// The small grey label over a figure.
pw.TextStyle pdfLabel(PdfFonts f) =>
    pw.TextStyle(font: f.medium, fontSize: 7.8, color: PdfInk.muted);

/// A light-sky pill: the dates a document covers, a member ID.
pw.Widget pdfChip(String text, PdfFonts f) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  decoration: pw.BoxDecoration(color: PdfInk.tint, borderRadius: pw.BorderRadius.circular(8)),
  child: pw.Text(text, style: pw.TextStyle(font: f.medium, fontSize: 8, color: PdfInk.navy)),
);

/// Dates as people say them: 3 Oct this year, 3 Oct 2025 otherwise.
String pdfShortDate(DateTime d) =>
    DateFormat(d.year == DateTime.now().year ? 'd MMM' : 'd MMM y').format(d);
