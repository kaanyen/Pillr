import 'package:intl/intl.dart';

import 'domain/partnership_entry.dart';
import 'fellowship_of.dart';

/// A calendar month bucket keyed by [year] and [month].
class MonthBucket implements Comparable<MonthBucket> {
  const MonthBucket({required this.year, required this.month});

  final int year;
  final int month;

  int get sortKey => year * 100 + month;

  DateTime get start => DateTime(year, month);

  bool contains(DateTime date) => date.year == year && date.month == month;

  String get label => DateFormat('MMMM yyyy').format(start);

  String get shortLabel => DateFormat('MMM yyyy').format(start);

  MonthBucket? previousMonth() {
    if (month == 1) return MonthBucket(year: year - 1, month: 12);
    return MonthBucket(year: year, month: month - 1);
  }

  MonthBucket? nextMonth() {
    if (month == 12) return MonthBucket(year: year + 1, month: 1);
    return MonthBucket(year: year, month: month + 1);
  }

  factory MonthBucket.fromDate(DateTime date) =>
      MonthBucket(year: date.year, month: date.month);

  @override
  int compareTo(MonthBucket other) => sortKey.compareTo(other.sortKey);

  @override
  bool operator ==(Object other) =>
      other is MonthBucket && other.sortKey == sortKey;

  @override
  int get hashCode => sortKey;
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.approvedTotal,
    required this.entryCount,
    required this.partnerCount,
    required this.fellowshipCount,
  });

  final MonthBucket month;
  final double approvedTotal;
  final int entryCount;
  final int partnerCount;
  final int fellowshipCount;
}

class MonthPartnerGiving {
  const MonthPartnerGiving({
    required this.partnerId,
    required this.partnerName,
    required this.totalCedis,
    required this.entryCount,
  });

  final String partnerId;
  final String partnerName;
  final double totalCedis;
  final int entryCount;
}

class MonthFellowshipGiving {
  const MonthFellowshipGiving({
    required this.fellowshipKey,
    required this.fellowshipName,
    required this.totalCedis,
    required this.partnerCount,
    required this.entryCount,
  });

  final String fellowshipKey;
  final String fellowshipName;
  final double totalCedis;
  final int partnerCount;
  final int entryCount;
}

/// Groups approved giving by the month it was given ([PartnershipEntry.dateGiven]).
abstract final class MonthlyRecords {
  static bool _isApproved(PartnershipEntry entry) => entry.status == 'approved';

  static Iterable<PartnershipEntry> _approvedInMonth(
    List<PartnershipEntry> entries,
    MonthBucket month,
  ) {
    return entries.where(
      (e) => _isApproved(e) && month.contains(e.dateGiven),
    );
  }

  /// Months that have at least one approved entry, newest first.
  static List<MonthBucket> monthsWithGiving(List<PartnershipEntry> entries) {
    final months = <int, MonthBucket>{};
    for (final entry in entries) {
      if (!_isApproved(entry)) continue;
      final bucket = MonthBucket.fromDate(entry.dateGiven);
      months[bucket.sortKey] = bucket;
    }
    return months.values.toList()..sort((a, b) => b.compareTo(a));
  }

  static MonthSummary summarize(
    List<PartnershipEntry> entries,
    MonthBucket month, {
    Map<String, String> fellowshipByPartnerId = const {},
  }) {
    final inMonth = _approvedInMonth(entries, month).toList();
    final partners = <String>{};
    final fellowships = <String>{};
    var total = 0.0;
    for (final entry in inMonth) {
      total += entry.amountCedis;
      partners.add(entry.partnerId);
      fellowships.add(fellowshipKeyOf(entry, fellowshipByPartnerId));
    }
    return MonthSummary(
      month: month,
      approvedTotal: total,
      entryCount: inMonth.length,
      partnerCount: partners.length,
      fellowshipCount: fellowships.length,
    );
  }

  static List<MonthSummary> allSummaries(List<PartnershipEntry> entries) {
    return [
      for (final month in monthsWithGiving(entries))
        summarize(entries, month),
    ];
  }

  static List<MonthPartnerGiving> partnersInMonth(
    List<PartnershipEntry> entries,
    MonthBucket month,
  ) {
    final totals = <String, double>{};
    final names = <String, String>{};
    final counts = <String, int>{};
    for (final entry in _approvedInMonth(entries, month)) {
      totals[entry.partnerId] =
          (totals[entry.partnerId] ?? 0) + entry.amountCedis;
      counts[entry.partnerId] = (counts[entry.partnerId] ?? 0) + 1;
      names[entry.partnerId] =
          entry.partnerSnapshot['fullName']?.toString() ?? 'Partner';
    }
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final row in rows)
        MonthPartnerGiving(
          partnerId: row.key,
          partnerName: names[row.key] ?? 'Partner',
          totalCedis: row.value,
          entryCount: counts[row.key] ?? 0,
        ),
    ];
  }

  static List<MonthPartnerGiving> partnersInMonthForFellowship(
    List<PartnershipEntry> entries,
    MonthBucket month,
    String fellowshipKey, {
    Map<String, String> fellowshipByPartnerId = const {},
  }) {
    final key = fellowshipKey.toLowerCase();
    final totals = <String, double>{};
    final names = <String, String>{};
    final counts = <String, int>{};
    for (final entry in _approvedInMonth(entries, month)) {
      if (fellowshipKeyOf(entry, fellowshipByPartnerId) != key) continue;
      totals[entry.partnerId] =
          (totals[entry.partnerId] ?? 0) + entry.amountCedis;
      counts[entry.partnerId] = (counts[entry.partnerId] ?? 0) + 1;
      names[entry.partnerId] =
          entry.partnerSnapshot['fullName']?.toString() ?? 'Partner';
    }
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final row in rows)
        MonthPartnerGiving(
          partnerId: row.key,
          partnerName: names[row.key] ?? 'Partner',
          totalCedis: row.value,
          entryCount: counts[row.key] ?? 0,
        ),
    ];
  }

  static List<MonthFellowshipGiving> fellowshipsInMonth(
    List<PartnershipEntry> entries,
    MonthBucket month, {
    Map<String, String> fellowshipByPartnerId = const {},
  }) {
    final totals = <String, double>{};
    final names = <String, String>{};
    final partners = <String, Set<String>>{};
    final counts = <String, int>{};
    for (final entry in _approvedInMonth(entries, month)) {
      final key = fellowshipKeyOf(entry, fellowshipByPartnerId);
      totals[key] = (totals[key] ?? 0) + entry.amountCedis;
      counts[key] = (counts[key] ?? 0) + 1;
      partners.putIfAbsent(key, () => {}).add(entry.partnerId);
      names.putIfAbsent(
        key,
        () => fellowshipLabelOf(entry, fellowshipByPartnerId),
      );
    }
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final row in rows)
        MonthFellowshipGiving(
          fellowshipKey: row.key,
          fellowshipName: names[row.key] ?? 'No fellowship',
          totalCedis: row.value,
          partnerCount: partners[row.key]?.length ?? 0,
          entryCount: counts[row.key] ?? 0,
        ),
    ];
  }

  /// Steps to the adjacent month that still has approved giving, if any.
  static MonthBucket? adjacentMonthWithGiving(
    List<PartnershipEntry> entries,
    MonthBucket from, {
    required bool forward,
  }) {
    final months = monthsWithGiving(entries);
    final index = months.indexWhere((m) => m == from);
    if (index < 0) return null;
    final nextIndex = forward ? index - 1 : index + 1;
    if (nextIndex < 0 || nextIndex >= months.length) return null;
    return months[nextIndex];
  }
}
