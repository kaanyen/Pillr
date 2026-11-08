import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/utils/text_case_utils.dart';
import '../arms/domain/arm_tree.dart';
import '../arms/domain/partnership_arm.dart';
import '../arms/providers/arms_providers.dart';
import '../entries/domain/partnership_entry.dart';
import '../entries/fellowship_of.dart';
import '../entries/providers/entries_providers.dart';
import '../partners/domain/partner.dart';
import '../partners/providers/partners_providers.dart';
import '../periods/domain/partnership_period.dart';
import '../periods/providers/periods_providers.dart';

/// One partner's approved giving in the active period, split the ways the
/// Records and Partners views show it.
class PartnerGiving {
  PartnerGiving({
    required this.partnerId,
    required this.name,
    required this.fellowshipKey,
    required this.fellowship,
  });

  final String partnerId;
  final String name;
  final String fellowshipKey;
  final String fellowship;
  final Map<String, double> byArm = {};
  final Map<int, double> byMonth = {};

  /// Giving per month per main arm.
  final Map<int, Map<String, double>> byArmMonth = {};
  double total = 0;
  int entries = 0;
  DateTime? lastGave;
  DateTime? firstGave;
}

/// One fellowship's approved giving in the active period.
class FellowshipGiving {
  FellowshipGiving({required this.key, required this.name});

  final String key;
  final String name;
  int partners = 0;
  final Set<String> gave = {};
  final Map<String, double> byArm = {};
  final Map<int, double> byMonth = {};
  double total = 0;
}

/// Approved giving in the active period, added up once for every view.
///
/// Arms are the church's main arms: a sub-arm's giving counts toward the arm
/// above it, the same way Overview and the arm totals count it. Months are
/// keyed `year * 12 + month - 1`, so a period that crosses New Year sorts
/// correctly.
class GivingView {
  GivingView._(
    this.arms,
    this.months,
    this.partners,
    this.fellowships,
    this.total,
    this.entryCount,
    this.armEntries,
    this.armByMonth,
    this.entriesByMonth,
  );

  final List<PartnershipArm> arms;
  final List<int> months;
  final List<PartnerGiving> partners;
  final List<FellowshipGiving> fellowships;
  final double total;
  final int entryCount;

  static int monthKey(DateTime d) => d.year * 12 + d.month - 1;
  static DateTime monthOf(int key) => DateTime(key ~/ 12, key % 12 + 1);

  double armTotal(String armId) =>
      partners.fold(0, (s, p) => s + (p.byArm[armId] ?? 0));
  double monthTotal(int month) =>
      partners.fold(0, (s, p) => s + (p.byMonth[month] ?? 0));

  /// Entries per main arm, for the By arm table.
  final Map<String, int> armEntries;

  /// Giving per month per main arm.
  final Map<int, Map<String, double>> armByMonth;

  /// Approved entries per month.
  final Map<int, int> entriesByMonth;

  FellowshipGiving? fellowship(String key) {
    for (final f in fellowships) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// 1-based place of [key] among fellowships for one arm, or for the total.
  int placeOf(String key, {String? armId}) {
    double v(FellowshipGiving f) =>
        armId == null ? f.total : (f.byArm[armId] ?? 0);
    final sorted = [...fellowships]..sort((a, b) => v(b).compareTo(v(a)));
    return sorted.indexWhere((f) => f.key == key) + 1;
  }

  static GivingView build({
    required List<PartnershipEntry> entries,
    required List<Partner> roster,
    required ArmTree tree,
    PartnershipPeriod? period,
  }) {
    final fellowshipById = {for (final p in roster) p.id: p.fellowship};
    final arms = tree.mains.where((a) => a.isActive).toList();

    // Every month of the period, so an empty month still shows as a row.
    final months = <int>[];
    if (period != null) {
      for (
        var m = monthKey(period.startDate);
        m <= monthKey(period.endDate);
        m++
      ) {
        months.add(m);
      }
    }

    final byPartner = <String, PartnerGiving>{};
    final byFellowship = <String, FellowshipGiving>{};
    FellowshipGiving fellowshipFor(String key, String label) => byFellowship
        .putIfAbsent(key, () => FellowshipGiving(key: key, name: label));

    for (final p in roster) {
      final key = p.fellowship.trim().toLowerCase();
      fellowshipFor(key, _label(p.fellowship)).partners++;
    }

    final armEntries = <String, int>{};
    final entriesByMonth = <int, int>{};
    final armByMonth = <int, Map<String, double>>{};
    var total = 0.0;
    var count = 0;
    for (final e in entries) {
      if (period != null && e.partnershipPeriodId != period.id) continue;
      final armId = tree.shownArmIdOf(e.partnershipArmId);
      final month = monthKey(e.dateGiven);
      final fKey = fellowshipKeyOf(e, fellowshipById);
      final fLabel = fellowshipLabelOf(e, fellowshipById);

      final p = byPartner.putIfAbsent(
        e.partnerId,
        () => PartnerGiving(
          partnerId: e.partnerId,
          name: e.partnerSnapshot['fullName']?.toString() ?? 'Partner',
          fellowshipKey: fKey,
          fellowship: fLabel,
        ),
      );
      p.total += e.amountCedis;
      p.entries++;
      p.byArm[armId] = (p.byArm[armId] ?? 0) + e.amountCedis;
      p.byMonth[month] = (p.byMonth[month] ?? 0) + e.amountCedis;
      final pm = p.byArmMonth.putIfAbsent(month, () => {});
      pm[armId] = (pm[armId] ?? 0) + e.amountCedis;
      if (p.lastGave == null || e.dateGiven.isAfter(p.lastGave!)) {
        p.lastGave = e.dateGiven;
      }
      if (p.firstGave == null || e.dateGiven.isBefore(p.firstGave!)) {
        p.firstGave = e.dateGiven;
      }

      final f = fellowshipFor(fKey, fLabel);
      f.total += e.amountCedis;
      f.gave.add(e.partnerId);
      f.byArm[armId] = (f.byArm[armId] ?? 0) + e.amountCedis;
      f.byMonth[month] = (f.byMonth[month] ?? 0) + e.amountCedis;

      armEntries[armId] = (armEntries[armId] ?? 0) + 1;
      entriesByMonth[month] = (entriesByMonth[month] ?? 0) + 1;
      final row = armByMonth.putIfAbsent(month, () => {});
      row[armId] = (row[armId] ?? 0) + e.amountCedis;

      total += e.amountCedis;
      count++;
    }

    final partners = byPartner.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final fellowships = byFellowship.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return GivingView._(
      arms,
      months,
      partners,
      fellowships,
      total,
      count,
      armEntries,
      armByMonth,
      entriesByMonth,
    );
  }
}

// Same label rule as fellowshipLabelOf, for a roster partner with no entry.
String _label(String raw) {
  final t = raw.trim();
  return t.isEmpty ? 'No fellowship' : TextCaseUtils.toTitleCase(t);
}

/// Approved giving in the active period, added up for every view at once.
final givingViewProvider = Provider.autoDispose<GivingView>((ref) {
  return GivingView.build(
    entries: ref.watch(rankingEntriesProvider).valueOrNull ?? const [],
    roster: ref.watch(visiblePartnersProvider(false)).valueOrNull ?? const [],
    tree: ref.watch(armTreeProvider),
    period: ref.watch(activePeriodProvider),
  );
});

/// True while the entries behind [givingViewProvider] are still loading.
final givingViewLoadingProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(rankingEntriesProvider).isLoading ||
      ref.watch(visiblePartnersProvider(false)).isLoading;
});
