import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_columns.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_models.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_review.dart';
import 'package:the_pillr/features/partners/domain/partner.dart';

/// Check rows: every option the row card and the sheet can show, pressed,
/// and what it asks the import to do.

final _arms = [
  for (final (id, name) in [('tithe', 'Tithe'), ('building', 'Building'), ('missions', 'Missions')])
    PartnershipArm(
      id: id,
      churchId: 'c',
      name: name,
      isActive: true,
      sortOrder: 0,
      createdBy: 'x',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
];

const _cols = [
  BulkImportColumn.date,
  BulkImportColumn.name,
  BulkImportColumn.contact,
  BulkImportColumn.memberId,
  BulkImportColumn.email,
  BulkImportColumn.fellowship,
  BulkImportColumn.category,
  BulkImportColumn.amount,
  BulkImportColumn.givenToNotes,
];

BulkRawRow _raw(int n, {String name = 'Ama Boateng', String amount = '500', String arm = 'Tithe', String fellowship = 'Bethel'}) =>
    BulkRawRow(
      sheetRowNumber: n,
      valuesByColumn: {
        BulkImportColumn.date: '1/11/2026',
        BulkImportColumn.name: name,
        BulkImportColumn.contact: '024412345$n',
        BulkImportColumn.memberId: 'DCC10000$n',
        BulkImportColumn.email: 'p$n@example.com',
        BulkImportColumn.fellowship: fellowship,
        BulkImportColumn.category: arm,
        BulkImportColumn.amount: amount,
        BulkImportColumn.givenToNotes: 'MoMo $n',
      },
    );

BulkResolvedRow _row(
  int n, {
  String name = 'Ama Boateng',
  double amount = 500,
  String? armId = 'tithe',
  String armName = 'Tithe',
  List<BulkImportIssue> issues = const [],
}) => BulkResolvedRow(
  sheetRowNumber: n,
  fullName: name,
  fellowship: 'Bethel',
  phone: '024412345$n',
  email: 'p$n@example.com',
  memberIdFromSheet: 'DCC10000$n',
  amountCedis: amount,
  dateGiven: DateTime(2026, 11, 1),
  armId: armId,
  armName: armName,
  periodId: 'p',
  periodName: '2026',
  notes: 'MoMo $n',
  pastorConfirmed: false,
  resolution: PartnerResolutionKind.createNew,
  partnerId: null,
  partner: null,
  issues: issues,
  isBlocking: issues.any((i) => i.severity == BulkImportSeverity.error),
);

BulkImportIssue _w(BulkImportIssueCode c, [String? m]) =>
    BulkImportIssue(code: c, severity: BulkImportSeverity.warning, message: m);
BulkImportIssue _e(BulkImportIssueCode c, [String? m]) =>
    BulkImportIssue(code: c, severity: BulkImportSeverity.error, message: m);

class _Calls {
  final edits = <(int, BulkImportColumn, String)>[];
  final kept = <int>[];
  final dropped = <int>[];
  final undone = <int>[];
  final mappedArms = <(List<String>, String)>[];
  final fellowships = <(List<String>, String, bool)>[];
  var applied = 0;
  var picks = 0;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  required List<BulkRawRow> raw,
  required List<BulkResolvedRow> resolved,
  Set<int> kept = const {},
  Set<int> dropped = const {},
  int settleSignal = 0,
  Size size = const Size(1400, 900),
  _Calls? reuse,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final calls = reuse ?? _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BulkImportReview(
          rawRows: raw,
          resolved: resolved,
          columns: _cols,
          arms: _arms,
          dayFirst: true,
          busy: false,
          money: (v) => '₵${v.toStringAsFixed(2)}',
          keptSheetRows: kept,
          droppedSheetRows: dropped,
          knownFellowships: const ['Bethel', 'Shiloh', 'Zion'],
          settleSignal: settleSignal,
          onEditCell: (i, c, v) => calls.edits.add((i, c, v)),
          onApplyFixes: (_) => calls.applied++,
          onKeepRow: calls.kept.add,
          onDropRow: calls.dropped.add,
          onUndoDecision: calls.undone.add,
          onBulkMapArm: (texts, arm) async => calls.mappedArms.add((texts, arm.name)),
          onBulkResolveFellowship: (texts, target, {required create}) async =>
              calls.fellowships.add((texts, target, create)),
          onPickPartner: () async {
            calls.picks++;
            return Partner(
              id: 'p9',
              churchId: 'c',
              memberId: 'DCC100099',
              fullName: 'Kweku Asamoah',
              fellowship: 'Zion',
              isActive: true,
              totalApprovedAmount: 0,
              entryCount: 0,
              createdBy: 'x',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('the sheet shows every column but member ID', (tester) async {
    await _pump(tester, raw: [_raw(3)], resolved: [_row(3)]);
    for (final h in ['Date', 'Name', 'Phone', 'Email', 'Fellowship', 'Arm', 'Amount', 'Notes']) {
      expect(find.text(h), findsWidgets, reason: 'column $h');
    }
    expect(find.text('Member ID'), findsNothing, reason: 'member ID is not shown');
    expect(find.text('0244123453'), findsWidgets);
    expect(find.text('DCC100003'), findsNothing);
    expect(find.text('MoMo 3'), findsWidgets);
  });

  testWidgets('a cell is typed into in place, like a spreadsheet', (tester) async {
    final calls = await _pump(tester, raw: [_raw(3)], resolved: [_row(3)]);
    // Click selects the cell; a second click on it starts typing.
    await tester.tap(find.text('0244123453').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('0244123453').last);
    await tester.pumpAndSettle();
    expect(find.text('Row 3 · Phone'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '0201112222');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(calls.edits.single, (0, BulkImportColumn.contact, '0201112222'));
  });

  testWidgets('two rows the same in the sheet: shown side by side; leave one out, or both are real', (tester) async {
    final dup = [_w(BulkImportIssueCode.duplicateInFile)];
    final calls = await _pump(
      tester,
      raw: [_raw(6), _raw(7)],
      resolved: [_row(6, issues: dup), _row(7, issues: dup)],
    );
    expect(find.text('Are rows 6 and 7 the same giving?'), findsOneWidget);
    expect(find.text('Row 6'), findsWidgets);
    expect(find.text('Row 7'), findsWidgets);
    await tester.tap(find.text('Leave row 7 out'));
    expect(calls.dropped, [7]);
    await tester.tap(find.text('Both are real'));
    expect(calls.kept, [6, 7]);
  });

  testWidgets('already in Pillr: it is new, or leave it out', (tester) async {
    final calls = await _pump(
      tester,
      raw: [_raw(5)],
      resolved: [_row(5, issues: [_w(BulkImportIssueCode.duplicateInDatabase, 'Already in Pillr since 2 Nov.')])],
    );
    expect(find.text('Is this already in Pillr?'), findsOneWidget);
    await tester.tap(find.text('It is new, bring it in'));
    expect(calls.kept, [5]);
    await tester.tap(find.text('Leave row 5 out'));
    expect(calls.dropped, [5]);
  });

  testWidgets('who is this partner: someone on the book, or keep it as it is', (tester) async {
    final calls = await _pump(
      tester,
      raw: [_raw(7, name: 'Kweku Asamoa')],
      resolved: [
        _row(7, name: 'Kweku Asamoa', issues: [_w(BulkImportIssueCode.possibleDuplicatePartner, 'Might be Kweku Asamoah.')]),
      ],
    );
    expect(find.text('Who is Kweku Asamoa?'), findsOneWidget);
    await tester.tap(find.text('Keep it as it is'));
    expect(calls.kept, [7], reason: 'Keep it as it is does something now');
    await tester.tap(find.text('Someone already on the book'));
    await tester.pumpAndSettle();
    expect(calls.picks, 1);
    expect(calls.edits, contains((0, BulkImportColumn.name, 'Kweku Asamoah')));
    expect(calls.edits, contains((0, BulkImportColumn.memberId, 'DCC100099')));
  });

  testWidgets('a row kept as it is moves to Ready, and can be asked again', (tester) async {
    final calls = await _pump(
      tester,
      raw: [_raw(7, name: 'Kweku Asamoa')],
      resolved: [
        _row(7, name: 'Kweku Asamoa', issues: [_w(BulkImportIssueCode.possibleDuplicatePartner, 'Might be Kweku Asamoah.')]),
      ],
      kept: {7},
    );
    expect(find.text('Row 7 comes in as it is'), findsOneWidget);
    expect(find.textContaining('Ready'), findsWidgets);
    await tester.tap(find.text('Undo: ask me again'));
    expect(calls.undone, [7]);
  });

  testWidgets('an amount that is not a number: fixed in the card', (tester) async {
    final calls = await _pump(
      tester,
      raw: [_raw(11, amount: 'abc')],
      resolved: [_row(11, amount: 0, issues: [_e(BulkImportIssueCode.invalidAmount, 'Amount isn’t a number')])],
    );
    expect(find.byType(TextField), findsWidgets);
    await tester.enterText(find.byType(TextField).last, '250');
    await tester.tap(find.text('Use this'));
    expect(calls.edits.last, (0, BulkImportColumn.amount, '250'));
    await tester.tap(find.text('Leave row 11 out'));
    expect(calls.dropped, [11]);
  });

  testWidgets('an arm the church does not have: pointed at one of its arms', (tester) async {
    final calls = await _pump(
      tester,
      raw: [_raw(9, arm: 'Tithee')],
      resolved: [_row(9, armId: null, armName: '', issues: [_e(BulkImportIssueCode.armNotFound)])],
    );
    await tester.tap(find.text('Pick an arm').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tithe').last);
    await tester.pumpAndSettle();
    expect(calls.mappedArms.single.$1, ['Tithee']);
    expect(calls.mappedArms.single.$2, 'Tithe');
  });

  testWidgets('a fellowship not in the book: use the close one for all, or create it', (tester) async {
    final unknown = [_w(BulkImportIssueCode.unknownFellowship)];
    final calls = await _pump(
      tester,
      raw: [_raw(16, fellowship: 'Shilo'), _raw(17, fellowship: 'Shilo')],
      resolved: [_row(16, issues: unknown), _row(17, issues: unknown)],
    );
    await tester.tap(find.text('Use Shiloh for all 2'));
    expect(calls.fellowships.last.$1, ['Shilo']);
    expect((calls.fellowships.last.$2, calls.fellowships.last.$3), ('Shiloh', false));
    await tester.tap(find.text('Create “Shilo”'));
    expect((calls.fellowships.last.$2, calls.fellowships.last.$3), ('Shilo', true));
  });

  testWidgets('a row left out can be brought back', (tester) async {
    final calls = await _pump(
      tester,
      raw: [_raw(4)],
      resolved: [_row(4, issues: [_w(BulkImportIssueCode.nameMismatch, 'Spelled differently')])],
      dropped: {4},
    );
    await tester.tap(find.textContaining('Left out', findRichText: true).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bring row 4 back'));
    expect(calls.undone, [4]);
  });

  testWidgets('tidy-ups Pillr suggests can be applied', (tester) async {
    final calls = await _pump(
      tester,
      raw: [_raw(3, name: 'ama boateng'), _raw(4, name: 'kofi mensah')],
      resolved: [_row(3), _row(4, name: 'Kofi Mensah')],
    );
    await tester.tap(find.text('Tidy-ups to apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply').first);
    expect(calls.applied, 1);
  });

  testWidgets('the card moves aside to a flap at the edge, and comes back', (tester) async {
    final dup = [_w(BulkImportIssueCode.duplicateInDatabase)];
    await _pump(tester, raw: [_raw(5), _raw(8)], resolved: [_row(5, issues: dup), _row(8, issues: dup)]);
    await tester.tap(find.text('Move aside'));
    await tester.pumpAndSettle();
    expect(find.text('need you'), findsOneWidget);
    expect(find.text('Is this already in Pillr?'), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Is this already in Pillr?'), findsOneWidget);
  });

  testWidgets('Settle N rows to continue moves the card to the next row', (tester) async {
    final dup = [_w(BulkImportIssueCode.duplicateInDatabase)];
    final raw = [_raw(5), _raw(8)];
    final resolved = [_row(5, issues: dup), _row(8, issues: dup)];
    final calls = await _pump(tester, raw: raw, resolved: resolved);
    expect(find.text('Row 5 · 1 of 2'), findsOneWidget);
    await _pump(tester, raw: raw, resolved: resolved, settleSignal: 1, reuse: calls);
    expect(find.text('Row 8 · 2 of 2'), findsOneWidget);
  });

  testWidgets('on a tablet the card comes up from the bottom and closes to a bar', (tester) async {
    final dup = [_w(BulkImportIssueCode.duplicateInDatabase)];
    await _pump(
      tester,
      raw: [_raw(5)],
      resolved: [_row(5, issues: dup)],
      size: const Size(800, 640),
    );
    expect(find.text('Is this already in Pillr?'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('1 row needs you'), findsOneWidget);
  });
}
