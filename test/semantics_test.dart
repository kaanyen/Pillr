import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:the_pillr/design/seline.dart';

/// The controls in this app are gesture detectors over painted boxes, which a
/// screen reader cannot see at all unless they say what they are. These assert
/// the saying, at the component level, where it covers every screen at once.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(theme: SelTheme.light(), home: Scaffold(body: Center(child: child))),
  );

  testWidgets('a button announces its label and that it is a button', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, SelButton(label: 'Approve all', onPressed: () {}));

    expect(
      tester.getSemantics(find.byType(SelButton)),
      matchesSemantics(label: 'Approve all', isButton: true, isEnabled: true, hasEnabledState: true, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('a disabled button says so rather than lying', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const SelButton(label: 'Approve all', onPressed: null));

    expect(
      tester.getSemantics(find.byType(SelButton)),
      matchesSemantics(
        label: 'Approve all',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    handle.dispose();
  });

  testWidgets('an icon-only button borrows its tooltip as a name', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      SelIconButton(icon: LucideIcons.search, tooltip: 'Search', onPressed: () {}),
    );

    // The label sits on the control itself, inside the tooltip wrapper.
    final node = tester.getSemantics(find.byIcon(LucideIcons.search));
    expect(node.label, contains('Search'));
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('a badge count is spoken, not just drawn', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      SelIconButton(
        icon: LucideIcons.bell,
        tooltip: 'Notifications',
        badge: 12,
        onPressed: () {},
      ),
    );

    expect(tester.getSemantics(find.byIcon(LucideIcons.bell)).label, 'Notifications, 12');
    handle.dispose();
  });

  testWidgets('a ledger row reads as one item', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      SizedBox(
        width: 800,
        child: SelLedger(
          minWidth: 400,
          columns: const [SelColumn('Partner'), SelColumn.numeric('Amount', width: 120)],
          rows: [
            SelRow(
              onTap: () {},
              cells: const [Text('Yaw Darko'), Text('GHS 300')],
            ),
          ],
        ),
      ),
    );

    // One node carrying both cells, not one node per column.
    final node = tester.getSemantics(find.text('Yaw Darko'));
    expect(node.label, contains('Yaw Darko'));
    expect(node.label, contains('GHS 300'));
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });
}
