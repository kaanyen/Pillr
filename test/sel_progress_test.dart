import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/design/seline.dart';

Future<void> _open(WidgetTester tester, Future<void> Function(BuildContext) go) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () => go(context), child: const Text('Go')),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Go'));
}

void main() {
  testWidgets('shows the count and the record it is on, then the summary', (tester) async {
    final gate = Completer<void>();
    var undone = false;
    await _open(
      tester,
      (context) => runWithProgress(
        context,
        title: 'Archiving October sheet',
        run: (p) async {
          p.start(3);
          p.tick('Ama Boateng · ₵500.00');
          p.tick('Kofi Mensah · ₵1,250.00');
          await gate.future;
          return SelSummary(
            title: 'October sheet is archived',
            numbers: const [('3', 'entries taken out')],
            lines: const [SelSummaryLine('Your pastor was told', ok: false)],
            actions: [SelSummaryAction('Bring it back', () => undone = true)],
          );
        },
      ),
    );
    await tester.pump();
    expect(find.text('Archiving October sheet'), findsOneWidget);
    expect(find.textContaining('2 of 3', findRichText: true), findsOneWidget);
    expect(find.textContaining('Kofi Mensah', findRichText: true), findsOneWidget);
    expect(find.text('Ama Boateng · ₵500.00'), findsOneWidget, reason: 'the one before moves to the done list');

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('October sheet is archived'), findsOneWidget);
    expect(find.text('entries taken out'), findsOneWidget);
    await tester.tap(find.text('Bring it back'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('October sheet is archived'), findsNothing, reason: 'the window closes first');
  });

  testWidgets('a server action moves through its named steps', (tester) async {
    final gate = Completer<int>();
    await _open(
      tester,
      (context) => runWithProgress(
        context,
        title: 'Merging Shilo into Shiloh',
        steps: const ['Checking', 'Moving them', 'Updating the totals'],
        run: (p) async {
          final n = await runServerSteps(p, () => gate.future);
          return SelSummary(title: '$n partners moved');
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Moving them'), findsOneWidget);
    gate.complete(23);
    await tester.pumpAndSettle();
    expect(find.text('23 partners moved'), findsOneWidget);
  });

  testWidgets('when it stops, it says how far it got and why, in plain words', (tester) async {
    await _open(
      tester,
      (context) => runWithProgress(
        context,
        title: 'Archiving October sheet',
        run: (p) async {
          p.start(14);
          p.tick('one');
          p.tick('two');
          throw StateError('boom');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archiving October sheet stopped'), findsOneWidget);
    expect(find.textContaining('2 of 14 was done'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing, reason: 'no raw error text');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Archiving October sheet stopped'), findsNothing);
  });
}
