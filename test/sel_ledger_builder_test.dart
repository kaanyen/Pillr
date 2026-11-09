import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/design/seline.dart';

/// `SelLedger.builder` exists so a long ledger costs the viewport rather than
/// the whole list. These assert the two halves of that bargain: rows off screen
/// are never built, and the ones on screen look the same as they did when every
/// row was handed over as a finished list.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: SelTheme.light(),
      home: Scaffold(
        body: SizedBox(width: 800, child: SingleChildScrollView(child: child)),
      ),
    ),
  );

  const columns = [
    SelColumn('Name', flex: 3),
    SelColumn.numeric('Amount', width: 130),
  ];

  testWidgets('builds only the rows the viewport needs', (tester) async {
    final built = <int>[];

    await pump(
      tester,
      SelLedger.builder(
        columns: columns,
        minWidth: 400,
        maxVirtualHeight: 460,
        itemCount: 500,
        itemBuilder: (context, i) {
          built.add(i);
          return SelRow(
            cells: [SelCell.primary('Partner $i'), SelCell.numeric('$i')],
          );
        },
      ),
    );

    // A 460px window at 46px a row shows ten, plus whatever the list caches
    // ahead. The number that matters is that it is nothing like 500.
    expect(built.length, lessThan(60));
    expect(find.text('Partner 0'), findsOneWidget);
    expect(find.text('Partner 499'), findsNothing);
  });

  testWidgets('renders the same rows as the list constructor', (tester) async {
    SelRow row(int i) => SelRow(
      cells: [SelCell.primary('Partner $i'), SelCell.numeric('${i * 10}')],
    );

    await pump(
      tester,
      SelLedger(
        columns: columns,
        minWidth: 400,
        rows: [for (var i = 0; i < 5; i++) row(i)],
      ),
    );
    expect(find.text('Partner 3'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);

    await pump(
      tester,
      SelLedger.builder(
        columns: columns,
        minWidth: 400,
        itemCount: 5,
        itemBuilder: (context, i) => row(i),
      ),
    );
    expect(find.text('Partner 3'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('an empty builder ledger shows the empty state', (tester) async {
    await pump(
      tester,
      SelLedger.builder(
        columns: columns,
        minWidth: 400,
        itemCount: 0,
        itemBuilder: (context, i) =>
            const SelRow(cells: [Text('unreachable'), Text('')]),
        emptyState: const SelEmpty(
          title: 'No partners yet',
          message: 'Add partners to start recording their giving.',
        ),
      ),
    );

    expect(find.text('No partners yet'), findsOneWidget);
    expect(find.text('unreachable'), findsNothing);
  });

  testWidgets('a short builder ledger sizes to its rows, not the cap', (
    tester,
  ) async {
    await pump(
      tester,
      SelLedger.builder(
        columns: columns,
        minWidth: 400,
        maxVirtualHeight: 640,
        showCaptions: false,
        itemCount: 3,
        itemBuilder: (context, i) =>
            SelRow(cells: [SelCell.primary('Partner $i'), SelCell.numeric('1')]),
      ),
    );

    // Three rows, not a 640px box with whitespace under them.
    expect(
      tester.getSize(find.byType(SelLedger)).height,
      closeTo(3 * kSelLedgerRowExtent + kSelLedgerFrame, 4),
    );
  });

  testWidgets('hasLeading reserves the leading column', (tester) async {
    await pump(
      tester,
      SelLedger.builder(
        columns: columns,
        minWidth: 400,
        hasLeading: true,
        itemCount: 3,
        itemBuilder: (context, i) => SelRow(
          leading: Checkbox(value: false, onChanged: (_) {}),
          cells: [SelCell.primary('Partner $i'), SelCell.numeric('1')],
        ),
      ),
    );

    expect(find.byType(Checkbox), findsNWidgets(3));
  });
}
