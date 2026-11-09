import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:the_pillr/design/seline.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: SelTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('primary buttons meet the 44px tap target', (tester) async {
    await pump(
      tester,
      SelButton.cyan(label: 'New entry', onPressed: () {}),
    );
    final box = tester.getSize(find.byType(SelButton));
    expect(box.height, greaterThanOrEqualTo(SelLayout.tapTarget));
  });

  testWidgets('icon buttons meet the 44px tap target', (tester) async {
    await pump(
      tester,
      SelIconButton(
        icon: LucideIcons.search,
        tooltip: 'Search',
        onPressed: () {},
      ),
    );
    final box = tester.getSize(find.byType(SelIconButton));
    expect(box.height, greaterThanOrEqualTo(SelLayout.tapTarget));
    expect(box.width, greaterThanOrEqualTo(SelLayout.tapTarget));
  });

  testWidgets('status pills meet the 44px tap target', (tester) async {
    await pump(
      tester,
      SelPillGroup<String>(
        selected: 'pending',
        onChanged: (_) {},
        options: const [('pending', 'Pending'), ('all', 'All')],
      ),
    );
    final group = tester.getSize(find.byType(SelPillGroup<String>));
    expect(group.height, greaterThanOrEqualTo(SelLayout.tapTarget));
  });
}
