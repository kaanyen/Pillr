import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/design/seline.dart';

/// Covers the auth-flow text links, which shipped unresponsive on web.
///
/// A bare `GestureDetector(child: Text(...))` does register taps in the widget
/// test environment, so the failure was not simply that Text refuses hits —
/// these tests pin the behaviour SelLink guarantees rather than asserting a
/// cause. The padded, opaque hit area is the part that matters: it is a real
/// target rather than the glyph bounds.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  testWidgets('SelLink fires when its label is tapped', (tester) async {
    var taps = 0;
    await pump(tester, SelLink(label: 'Back', onTap: () => taps++));

    await tester.tap(find.text('Back'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('SelLink is hittable in its padding, not just on the glyphs',
      (tester) async {
    var taps = 0;
    await pump(tester, SelLink(label: 'Back', onTap: () => taps++));

    // Just inside the padded edge — a bare Text would miss here.
    final box = tester.getRect(find.byType(SelLink));
    await tester.tapAt(Offset(box.left + 2, box.center.dy));
    await tester.pump();

    expect(taps, 1, reason: 'padding must be part of the tap target');
  });

  testWidgets('SelLink with a null onTap is inert but still renders',
      (tester) async {
    await pump(tester, const SelLink(label: 'Back', onTap: null));
    expect(find.text('Back'), findsOneWidget);
  });
}
