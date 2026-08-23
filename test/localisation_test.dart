import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/auth/domain/user_church_index.dart';
import 'package:the_pillr/l10n/app_localizations.dart';
import 'package:the_pillr/shell/nav_model.dart';

/// The ARB files carried 235 keys while the interface was hardcoded English:
/// the French build looked translated and wasn't. These check the navigation —
/// the one part of the app every screen shows — actually changes language.
void main() {
  Future<AppLocalizations> localisationsFor(WidgetTester tester, Locale locale) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return l10n;
  }

  final pastor = UserChurchIndex(uid: 'u1', churchId: 'c1', role: 'pastor');

  testWidgets('the rail is in English for en', (tester) async {
    final l10n = await localisationsFor(tester, const Locale('en'));
    final labels = navGroupsFor(pastor, l10n).expand((g) => g.items).map((i) => i.label);
    expect(labels, containsAll(['Overview', 'Queue', 'Records', 'Partners']));
  });

  testWidgets('the rail is in French for fr', (tester) async {
    final l10n = await localisationsFor(tester, const Locale('fr'));
    final labels = navGroupsFor(pastor, l10n).expand((g) => g.items).map((i) => i.label).toList();
    expect(labels, containsAll(["Vue d'ensemble", "File d'attente", 'Registres']));
    expect(labels, isNot(contains('Overview')));
  });

  testWidgets('the compact bar translates too', (tester) async {
    final l10n = await localisationsFor(tester, const Locale('fr'));
    expect(mobileNavFor(pastor, l10n).map((i) => i.label), contains('Registres'));
  });

  testWidgets('every key the navigation needs exists in French', (tester) async {
    final fr = await localisationsFor(tester, const Locale('fr'));
    final en = await localisationsFor(tester, const Locale('en'));
    // A key missing from app_fr.arb silently falls back to English, which is
    // how a half-translated build passes unnoticed.
    for (final pair in [
      (fr.navOverview, en.navOverview),
      (fr.navQueue, en.navQueue),
      (fr.navRecords, en.navRecords),
      (fr.navPeople, en.navPeople),
      (fr.queueSubtitle, en.queueSubtitle),
      (fr.searchIdleTitle, en.searchIdleTitle),
    ]) {
      expect(pair.$1, isNot(pair.$2), reason: 'untranslated: ${pair.$2}');
    }
  });
}
