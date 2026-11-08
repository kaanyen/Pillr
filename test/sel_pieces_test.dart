import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/design/seline.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('selInitials takes up to two initials', () {
    expect(selInitials('Ama Boateng'), 'AB');
    expect(selInitials('  kofi  '), 'K');
    expect(selInitials('Paa Kwesi Hagan'), 'PK');
    expect(selInitials(''), '');
  });

  testWidgets('SelCountTabs shows counts and reports the tab tapped', (t) async {
    String? picked;
    await t.pumpWidget(_wrap(SelCountTabs<String>(
      selected: 'a',
      onSelect: (v) => picked = v,
      tabs: const [('a', 'Need you', 4), ('b', 'Ready', 12)],
    )));
    expect(find.text('Need you'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    await t.tap(find.text('Ready'));
    expect(picked, 'b');
  });

  testWidgets('SelBreadcrumb links every part but the last', (t) async {
    var went = false;
    await t.pumpWidget(_wrap(SelBreadcrumb([
      ('Partners', () => went = true),
      ('Abena Darko', null),
    ])));
    expect(find.byType(SelLink), findsOneWidget);
    await t.tap(find.text('Partners'));
    expect(went, isTrue);
    expect(find.text('Abena Darko'), findsOneWidget);
  });

  testWidgets('SelNavyCard runs its action', (t) async {
    var tapped = false;
    await t.pumpWidget(_wrap(SelNavyCard(
      label: 'Needs you',
      headline: '2 invites',
      sub: 'Not accepted yet',
      action: 'Open People',
      onAction: () => tapped = true,
    )));
    await t.tap(find.text('Open People'));
    expect(tapped, isTrue);
  });
}
