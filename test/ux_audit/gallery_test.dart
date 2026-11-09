import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:the_pillr/design/seline.dart';

/// Captures Seline compositions to PNG for the Laws of UX before/after set.
///
///   UX_AUDIT_PHASE=before flutter test --update-goldens test/ux_audit/gallery_test.dart
///   UX_AUDIT_PHASE=after  flutter test --update-goldens test/ux_audit/gallery_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final phase = Platform.environment['UX_AUDIT_PHASE'];
  final capturing = phase == 'before' || phase == 'after';
  final after = phase == 'after';
  _auditAfter = after;

  if (!capturing) {
    test('gallery captures are opt-in via UX_AUDIT_PHASE', () {});
    return;
  }

  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'));
    await inter.load();
    final tight = FontLoader('InterTight')
      ..addFont(rootBundle.load('assets/fonts/InterTight-Regular.ttf'));
    await tight.load();
    final lucide = FontLoader('Lucide')
      ..addFont(rootBundle.load('assets/fonts/lucide.ttf'));
    await lucide.load();
  });

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Widget scene,
    Size size = const Size(880, 420),
    bool requestFocus = false,
  }) async {
    tester.view.physicalSize = Size(size.width * 2, size.height * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SelTheme.light(),
        home: Scaffold(
          backgroundColor: Sel.canvas,
          body: Center(
            child: RepaintBoundary(
              key: const Key('scene'),
              child: ColoredBox(
                color: Sel.canvas,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: scene,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Finite pumps — TextField caret and hover animations never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    if (requestFocus) {
      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byKey(const Key('scene')),
      matchesGoldenFile('../../docs/ux-audit/screenshots/${phase!}/$name.png'),
    );
  }

  testWidgets('01 sign-in fields', (tester) async {
    await capture(
      tester,
      name: '01-signin-fields',
      requestFocus: true,
      size: const Size(560, 440),
      scene: const SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Welcome back', style: SelType.title),
            SizedBox(height: 8),
            Text(
              'Sign in to your church workspace.',
              style: SelType.bodyMuted,
            ),
            SizedBox(height: 24),
            SelField(
              label: 'Email',
              hint: 'you@church.org',
              helper: 'Work email — optional alias is fine',
              prefixIcon: LucideIcons.mail,
            ),
            SizedBox(height: 16),
            SelField(
              label: 'Password',
              hint: 'Your password',
              obscureText: true,
              prefixIcon: LucideIcons.lock,
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('02 action pills', (tester) async {
    await capture(
      tester,
      name: '02-action-pills',
      size: const Size(800, 260),
      scene: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelButton.cyan(
            label: 'New entry',
            icon: LucideIcons.plus,
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          SelButton(
            label: 'Import',
            icon: LucideIcons.upload,
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          SelButton(
            label: 'Open queue',
            kind: SelButtonKind.quiet,
            trailingIcon: LucideIcons.arrowRight,
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          SelIconButton(
            icon: LucideIcons.search,
            tooltip: 'Search',
            onPressed: () {},
          ),
          SelIconButton(
            icon: LucideIcons.bell,
            tooltip: 'Notifications',
            badge: 4,
            onPressed: () {},
          ),
        ],
      ),
    );
  });

  testWidgets('03 status pills', (tester) async {
    await capture(
      tester,
      name: '03-status-pills',
      size: const Size(800, 260),
      scene: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('QUEUE', style: SelType.caption),
          const SizedBox(height: 8),
          SelPillGroup<String>(
            selected: 'pending',
            onChanged: (_) {},
            options: const [
              ('all', 'All (128)'),
              ('pending', 'Pending'),
              ('approved', 'Approved'),
              ('declined', 'Declined'),
            ],
          ),
        ],
      ),
    );
  });

  testWidgets('04 overview header', (tester) async {
    await capture(
      tester,
      name: '04-overview-header',
      size: const Size(1100, 520),
      scene: SizedBox(
        width: 1000,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelPageTitle.hero(
              title: 'Good evening, ',
              highlight: 'Ama',
              subtitle:
                  'Partnership activity across Demo Community Church, updating live.',
              actions: [
                SelButton.cyan(
                  label: 'New entry',
                  icon: LucideIcons.plus,
                  onPressed: () {},
                ),
              ],
            ),
            SelStatRow(
              stats: const [
                SelStat(
                  label: 'Approved',
                  value: '₵48.2k',
                  footnote: '312 entries',
                ),
                SelStat(
                  label: 'Awaiting review',
                  value: '4',
                  footnote: 'In your queue',
                ),
                SelStat(
                  label: 'Active partners',
                  value: '186',
                  footnote: 'Giving records',
                ),
                SelStat(
                  label: 'Goal progress',
                  value: '72%',
                  footnote: 'Q3 Partnership',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('05 waiting on you', (tester) async {
    final panel = SelPanel(
      title: 'Waiting on you',
      subtitle: after
          ? '4 entries still open — the queue is waiting'
          : '4 entries to review',
      trailing: SelButton(
        label: 'Open queue',
        kind: SelButtonKind.quiet,
        dense: true,
        trailingIcon: LucideIcons.arrowRight,
        onPressed: () {},
      ),
      contentPadding: EdgeInsets.zero,
      child: const Column(
        children: [
          _PendingRow('Kwame Mensah', 'Missions', '₵500'),
          Divider(height: 1, color: Sel.border),
          _PendingRow('Abena Osei', 'Building', '₵1,200'),
          Divider(height: 1, color: Sel.border),
          _PendingRow('Yaw Darko', 'Media', '₵80'),
        ],
      ),
    );
    await capture(
      tester,
      name: '05-waiting-on-you',
      size: const Size(900, 380),
      scene: SizedBox(
        width: 800,
        child: after
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SelRadius.card),
                  border: const Border(
                    left: BorderSide(color: Sel.warning, width: 3),
                  ),
                ),
                child: panel,
              )
            : panel,
      ),
    );
  });

  testWidgets('06 goals', (tester) async {
    await capture(
      tester,
      name: '06-goals',
      size: const Size(720, 320),
      scene: const SizedBox(
        width: 560,
        child: SelCard(
          child: SelGoalLine(
            color: Color(0xFF4C5C8A),
            label: 'Missions',
            value: 14400,
            target: 20000,
            valueText: '₵14,400',
            targetText: '₵20,000',
          ),
        ),
      ),
    );
  });

  testWidgets('07 filter chips', (tester) async {
    await capture(
      tester,
      name: '07-filter-chips',
      size: const Size(800, 240),
      scene: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _FakeFilterChip(label: 'When', value: 'This month'),
          _FakeFilterChip(label: 'Arm', value: 'Missions'),
          _FakeAddFilter(),
          SelButton(
            label: 'Clear',
            kind: SelButtonKind.quiet,
            onPressed: () {},
          ),
        ],
      ),
    );
  });

  testWidgets('08 account chip', (tester) async {
    await capture(
      tester,
      name: '08-account-chip',
      size: const Size(480, 220),
      scene: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelIconButton(
            icon: LucideIcons.search,
            tooltip: 'Search',
            onPressed: () {},
          ),
          SelIconButton(
            icon: LucideIcons.bell,
            tooltip: 'Notifications',
            badge: 4,
            onPressed: () {},
          ),
          const SizedBox(width: 4),
          _FakeAccountChip(),
        ],
      ),
    );
  });
}

bool _auditAfter = false;

class _PendingRow extends StatelessWidget {
  const _PendingRow(this.name, this.arm, this.amount);

  final String name;
  final String arm;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(child: SelCell.stacked(name, arm)),
          Text(amount, style: SelType.bodyMedium),
          const SizedBox(width: 24),
          const SelStatusMark(
            status: SelStatus.pending,
            label: 'Pending',
            iconOnly: true,
          ),
        ],
      ),
    );
  }
}

class _FakeFilterChip extends StatelessWidget {
  const _FakeFilterChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final chrome = _auditAfter ? Sel.warm : Sel.ash;
    return Container(
      constraints: _auditAfter
          ? const BoxConstraints(minHeight: 44)
          : const BoxConstraints(),
      decoration: BoxDecoration(
        color: Sel.card,
        border: Border.all(color: Sel.border),
        borderRadius: BorderRadius.circular(SelRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, _auditAfter ? 10 : 8, 8, _auditAfter ? 10 : 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$label ', style: SelType.small),
                Text(value, style: SelType.small.copyWith(color: Sel.ink)),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronDown, size: _auditAfter ? 13 : 11, color: chrome),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(4, _auditAfter ? 10 : 8, 12, _auditAfter ? 10 : 8),
            child: Icon(LucideIcons.x, size: _auditAfter ? 14 : 12, color: chrome),
          ),
        ],
      ),
    );
  }
}

class _FakeAddFilter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: _auditAfter
          ? const BoxConstraints(minHeight: 44)
          : const BoxConstraints(),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: _auditAfter ? 10 : 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Sel.border),
        borderRadius: BorderRadius.circular(SelRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.plus, size: _auditAfter ? 14 : 12, color: _auditAfter ? Sel.warm : Sel.ash),
          const SizedBox(width: 8),
          Text('Add filter', style: SelType.small.copyWith(color: Sel.ink)),
        ],
      ),
    );
  }
}

class _FakeAccountChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: _auditAfter
          ? const BoxConstraints(minHeight: 44)
          : const BoxConstraints(),
      padding: EdgeInsets.fromLTRB(_auditAfter ? 6 : 4, _auditAfter ? 6 : 4, 12, _auditAfter ? 6 : 4),
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(SelRadius.pill),
        border: Border.all(color: Sel.border),
        boxShadow: SelShadow.hairline,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 22,
            width: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Sel.canvas,
              shape: BoxShape.circle,
            ),
            child: Text(
              'A',
              style: SelType.small.copyWith(
                color: Sel.ink,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('Ama', style: SelType.button),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronDown, size: 13, color: _auditAfter ? Sel.warm : Sel.ash),
        ],
      ),
    );
  }
}
