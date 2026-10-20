import 'domain/partnership_entry.dart';
import 'fellowship_of.dart';
import 'monthly_records_models.dart';

/// Precomputed monthly giving aggregates — one pass over entries.
class MonthlyRecordsIndex {
  MonthlyRecordsIndex._({
    required this.summaries,
    required this.monthOrder,
    required this.partnersByMonth,
    required this.fellowshipsByMonth,
    required this.partnersByMonthFellowship,
  });

  final List<MonthSummary> summaries;
  final List<MonthBucket> monthOrder;
  final Map<MonthBucket, List<MonthPartnerGiving>> partnersByMonth;
  final Map<MonthBucket, List<MonthFellowshipGiving>> fellowshipsByMonth;
  final Map<MonthBucket, Map<String, List<MonthPartnerGiving>>>
      partnersByMonthFellowship;

  factory MonthlyRecordsIndex.build(
    List<PartnershipEntry> entries, {
    Map<String, String> fellowshipByPartnerId = const {},
  }) {
    final summaryData = <MonthBucket, _MonthAccumulator>{};

    for (final entry in entries) {
      if (entry.status != 'approved') continue;
      final month = MonthBucket.fromDate(entry.dateGiven);
      final fellowshipKey = fellowshipKeyOf(entry, fellowshipByPartnerId);
      final acc = summaryData.putIfAbsent(month, _MonthAccumulator.new);

      acc.total += entry.amountCedis;
      acc.entryCount++;
      acc.partners.add(entry.partnerId);
      acc.fellowships.add(fellowshipKey);
      acc.fellowshipNames.putIfAbsent(
        fellowshipKey,
        () => fellowshipLabelOf(entry, fellowshipByPartnerId),
      );

      acc.partnerTotals[entry.partnerId] =
          (acc.partnerTotals[entry.partnerId] ?? 0) + entry.amountCedis;
      acc.partnerCounts[entry.partnerId] =
          (acc.partnerCounts[entry.partnerId] ?? 0) + 1;
      acc.partnerNames[entry.partnerId] =
          entry.partnerSnapshot['fullName']?.toString() ?? 'Partner';

      acc.fellowshipTotals[fellowshipKey] =
          (acc.fellowshipTotals[fellowshipKey] ?? 0) + entry.amountCedis;
      acc.fellowshipCounts[fellowshipKey] =
          (acc.fellowshipCounts[fellowshipKey] ?? 0) + 1;
      acc.fellowshipPartners
          .putIfAbsent(fellowshipKey, () => {})
          .add(entry.partnerId);

      acc.addFellowshipPartner(fellowshipKey, entry.partnerId, entry.amountCedis);
    }

    final monthOrder = summaryData.keys.toList()..sort((a, b) => b.compareTo(a));
    final summaries = [
      for (final month in monthOrder)
        MonthSummary(
          month: month,
          approvedTotal: summaryData[month]!.total,
          entryCount: summaryData[month]!.entryCount,
          partnerCount: summaryData[month]!.partners.length,
          fellowshipCount: summaryData[month]!.fellowships.length,
        ),
    ];

    final partnersByMonth = <MonthBucket, List<MonthPartnerGiving>>{};
    final fellowshipsByMonth = <MonthBucket, List<MonthFellowshipGiving>>{};
    final partnersByMonthFellowship =
        <MonthBucket, Map<String, List<MonthPartnerGiving>>>{};

    for (final month in monthOrder) {
      final acc = summaryData[month]!;
      partnersByMonth[month] = _partnerRows(acc);
      fellowshipsByMonth[month] = _fellowshipRows(acc);
      partnersByMonthFellowship[month] = _partnersByFellowship(acc);
    }

    return MonthlyRecordsIndex._(
      summaries: summaries,
      monthOrder: monthOrder,
      partnersByMonth: partnersByMonth,
      fellowshipsByMonth: fellowshipsByMonth,
      partnersByMonthFellowship: partnersByMonthFellowship,
    );
  }

  MonthSummary? summaryFor(MonthBucket month) {
    for (final s in summaries) {
      if (s.month == month) return s;
    }
    return null;
  }

  MonthBucket? adjacentMonth(MonthBucket from, {required bool forward}) {
    final index = monthOrder.indexWhere((m) => m == from);
    if (index < 0) return null;
    final nextIndex = forward ? index - 1 : index + 1;
    if (nextIndex < 0 || nextIndex >= monthOrder.length) return null;
    return monthOrder[nextIndex];
  }

  List<MonthPartnerGiving> partnersInMonth(MonthBucket month) =>
      partnersByMonth[month] ?? const [];

  List<MonthFellowshipGiving> fellowshipsInMonth(MonthBucket month) =>
      fellowshipsByMonth[month] ?? const [];

  List<MonthPartnerGiving> partnersInMonthForFellowship(
    MonthBucket month,
    String fellowshipKey,
  ) =>
      partnersByMonthFellowship[month]?[fellowshipKey.toLowerCase()] ??
      const [];

  static List<MonthPartnerGiving> _partnerRows(_MonthAccumulator acc) {
    final rows = acc.partnerTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final row in rows)
        MonthPartnerGiving(
          partnerId: row.key,
          partnerName: acc.partnerNames[row.key] ?? 'Partner',
          totalCedis: row.value,
          entryCount: acc.partnerCounts[row.key] ?? 0,
        ),
    ];
  }

  static List<MonthFellowshipGiving> _fellowshipRows(_MonthAccumulator acc) {
    final rows = acc.fellowshipTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final row in rows)
        MonthFellowshipGiving(
          fellowshipKey: row.key,
          fellowshipName: acc.fellowshipNames[row.key] ?? 'No fellowship',
          totalCedis: row.value,
          partnerCount: acc.fellowshipPartners[row.key]?.length ?? 0,
          entryCount: acc.fellowshipCounts[row.key] ?? 0,
        ),
    ];
  }

  static Map<String, List<MonthPartnerGiving>> _partnersByFellowship(
    _MonthAccumulator acc,
  ) {
    return acc.partnersByFellowship.map((key, partnerTotals) {
      final sorted = partnerTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return MapEntry(
        key,
        [
          for (final row in sorted)
            MonthPartnerGiving(
              partnerId: row.key,
              partnerName: acc.partnerNames[row.key] ?? 'Partner',
              totalCedis: row.value,
              entryCount: acc.partnerCounts[row.key] ?? 0,
            ),
        ],
      );
    });
  }
}

class _MonthAccumulator {
  double total = 0;
  int entryCount = 0;
  final partners = <String>{};
  final fellowships = <String>{};
  final partnerTotals = <String, double>{};
  final partnerCounts = <String, int>{};
  final partnerNames = <String, String>{};
  final fellowshipTotals = <String, double>{};
  final fellowshipCounts = <String, int>{};
  final fellowshipNames = <String, String>{};
  final fellowshipPartners = <String, Set<String>>{};
  final partnersByFellowship = <String, Map<String, double>>{};

  void addFellowshipPartner(String fellowshipKey, String partnerId, double amount) {
    final bucket =
        partnersByFellowship.putIfAbsent(fellowshipKey, () => <String, double>{});
    bucket[partnerId] = (bucket[partnerId] ?? 0) + amount;
  }
}
