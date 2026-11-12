import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/core/utils/follow_up_export.dart';

final _now = DateTime(2026, 11, 12, 9, 30);

List<FollowUpRow> _rows(int n) => [
  for (var i = 0; i < n; i++)
    FollowUpRow(
      name: i == 1 ? 'Ama "Akos" Boateng' : 'Partner ${i + 1}',
      memberId: 'DCC1000${i.toString().padLeft(2, '0')}',
      fellowship: i.isEven ? 'Zion' : 'Bethel',
      phones: i % 3 == 0 ? const [] : ['024 555 01${i.toString().padLeft(2, '0')}', if (i == 2) '020 111 2222'],
      lastGave: i % 4 == 0 ? null : _now.subtract(Duration(days: 95 + i)),
      reason: i == 2 ? 'Travelling, back in December' : '',
    ),
];

const _h = (church: 'Demo Community Church', window: '90 days', by: 'Demo Pastor');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('CSV has a heading, one line per partner, every phone, and quotes what needs it', () {
    final csv = followUpCsv(_rows(5), now: _now);
    final lines = csv.trim().split('\r\n');
    expect(lines.first, 'Partner,Member ID,Fellowship,Phone,Other phones,Last gave,Days since,Reason');
    expect(lines, hasLength(6));
    expect(lines[1], startsWith('Partner 1,DCC100000,Zion,,,Not yet,,'));
    expect(lines[2], contains('"Ama ""Akos"" Boateng"'));
    expect(lines[3], contains('024 555 0102,020 111 2222'));
    expect(lines[3], contains('"Travelling, back in December"'));
    expect(lines[3], contains(',97,'), reason: 'days since last gave');
  });

  test('PDF builds for a short list and a long one', () async {
    final h = FollowUpHeader(church: _h.church, window: _h.window, madeBy: _h.by, madeAt: _now);
    final small = await buildFollowUpPdfBytes(_rows(6), h);
    final big = await buildFollowUpPdfBytes(_rows(140), h);
    expect(String.fromCharCodes(small.take(5)), '%PDF-');
    expect(big.length, greaterThan(small.length));
    final out = Platform.environment['FOLLOW_UP_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(big);
  });

  test('an empty list still makes a PDF that says so', () async {
    final h = FollowUpHeader(church: _h.church, window: '60 days', madeBy: _h.by, madeAt: _now);
    final bytes = await buildFollowUpPdfBytes(const [], h);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
