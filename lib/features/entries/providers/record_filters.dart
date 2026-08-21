import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/partnership_entry.dart';

/// Windows people actually ask for — "what came in this month", not a date
/// picker they have to fill in twice.
enum RecordDateRange {
  last7('Last 7 days'),
  last30('Last 30 days'),
  thisMonth('This month'),
  lastMonth('Last month'),
  thisYear('This year');

  const RecordDateRange(this.label);
  final String label;
}

enum RecordAmountBand {
  under100('Under ₵100', 0, 100),
  from100to500('₵100 – ₵500', 100, 500),
  from500to1000('₵500 – ₵1,000', 500, 1000),
  over1000('₵1,000 and above', 1000, double.infinity);

  const RecordAmountBand(this.label, this.min, this.maxExclusive);
  final String label;
  final double min;
  final double maxExclusive;

  bool contains(double amount) => amount >= min && amount < maxExclusive;
}

/// The kinds of filter that can be on at once.
enum RecordFilterKind { dateRange, fellowship, arm, amount, recordedBy }

/// Filters shared by Records and the ranked partners view.
///
/// The two are the same question asked twice — "what happened, and who gave
/// the most" — so a filter set on one is meaningless if the other ignores it.
///
/// At most [maxActive] can be on at once. This is a deliberate limit: three
/// stacked filters produce an empty list often enough that people conclude
/// the data is missing rather than that they over-filtered.
class RecordFilters extends Equatable {
  const RecordFilters({
    this.dateRange,
    this.fellowship,
    this.armId,
    this.amount,
    this.recordedBy,
  });

  static const maxActive = 2;
  static const empty = RecordFilters();

  final RecordDateRange? dateRange;
  final String? fellowship;
  final String? armId;
  final RecordAmountBand? amount;
  final String? recordedBy;

  bool isOn(RecordFilterKind kind) => switch (kind) {
    RecordFilterKind.dateRange => dateRange != null,
    RecordFilterKind.fellowship => fellowship != null,
    RecordFilterKind.arm => armId != null,
    RecordFilterKind.amount => amount != null,
    RecordFilterKind.recordedBy => recordedBy != null,
  };

  List<RecordFilterKind> get active => [
    for (final k in RecordFilterKind.values)
      if (isOn(k)) k,
  ];

  int get activeCount => active.length;
  bool get isFull => activeCount >= maxActive;
  bool get isEmpty => activeCount == 0;

  /// Whether [kind] can be switched on — an already-on filter can always be
  /// changed, but a new one has to wait for a slot.
  bool canAdd(RecordFilterKind kind) => isOn(kind) || !isFull;

  RecordFilters without(RecordFilterKind kind) => RecordFilters(
    dateRange: kind == RecordFilterKind.dateRange ? null : dateRange,
    fellowship: kind == RecordFilterKind.fellowship ? null : fellowship,
    armId: kind == RecordFilterKind.arm ? null : armId,
    amount: kind == RecordFilterKind.amount ? null : amount,
    recordedBy: kind == RecordFilterKind.recordedBy ? null : recordedBy,
  );

  RecordFilters withDateRange(RecordDateRange? v) =>
      _replace(RecordFilterKind.dateRange, dateRange: v);
  RecordFilters withFellowship(String? v) =>
      _replace(RecordFilterKind.fellowship, fellowship: v);
  RecordFilters withArm(String? v) => _replace(RecordFilterKind.arm, armId: v);
  RecordFilters withAmount(RecordAmountBand? v) =>
      _replace(RecordFilterKind.amount, amount: v);
  RecordFilters withRecordedBy(String? v) =>
      _replace(RecordFilterKind.recordedBy, recordedBy: v);

  RecordFilters _replace(
    RecordFilterKind kind, {
    RecordDateRange? dateRange,
    String? fellowship,
    String? armId,
    RecordAmountBand? amount,
    String? recordedBy,
  }) {
    final clearing =
        dateRange == null &&
        fellowship == null &&
        armId == null &&
        amount == null &&
        recordedBy == null;
    if (clearing) return without(kind);
    // Turning on a third filter would silently drop one; refuse instead.
    if (!canAdd(kind)) return this;
    return RecordFilters(
      dateRange: kind == RecordFilterKind.dateRange
          ? dateRange
          : this.dateRange,
      fellowship: kind == RecordFilterKind.fellowship
          ? fellowship
          : this.fellowship,
      armId: kind == RecordFilterKind.arm ? armId : this.armId,
      amount: kind == RecordFilterKind.amount ? amount : this.amount,
      recordedBy: kind == RecordFilterKind.recordedBy
          ? recordedBy
          : this.recordedBy,
    );
  }

  @override
  List<Object?> get props => [dateRange, fellowship, armId, amount, recordedBy];
}

/// Start of the window [range] describes, relative to [now].
DateTime recordRangeStart(RecordDateRange range, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return switch (range) {
    RecordDateRange.last7 => today.subtract(const Duration(days: 6)),
    RecordDateRange.last30 => today.subtract(const Duration(days: 29)),
    RecordDateRange.thisMonth => DateTime(now.year, now.month),
    RecordDateRange.lastMonth => DateTime(now.year, now.month - 1),
    RecordDateRange.thisYear => DateTime(now.year),
  };
}

/// End of the window, exclusive.
DateTime recordRangeEnd(RecordDateRange range, DateTime now) {
  final tomorrow = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));
  return switch (range) {
    // Last month is the only closed window: it ends where this month starts.
    RecordDateRange.lastMonth => DateTime(now.year, now.month),
    _ => tomorrow,
  };
}

/// Applies [filters] to [entries]. Pure, so both views filter identically.
List<PartnershipEntry> applyRecordFilters(
  List<PartnershipEntry> entries,
  RecordFilters filters, {
  required DateTime now,
}) {
  if (filters.isEmpty) return entries;

  final range = filters.dateRange;
  final from = range == null ? null : recordRangeStart(range, now);
  final to = range == null ? null : recordRangeEnd(range, now);
  final fellowship = filters.fellowship?.toLowerCase();

  return [
    for (final e in entries)
      if (_matches(e, filters, from, to, fellowship)) e,
  ];
}

bool _matches(
  PartnershipEntry e,
  RecordFilters f,
  DateTime? from,
  DateTime? to,
  String? fellowship,
) {
  if (from != null && to != null) {
    if (e.dateGiven.isBefore(from) || !e.dateGiven.isBefore(to)) return false;
  }
  if (fellowship != null) {
    final v = e.partnerSnapshot['fellowship']?.toString().toLowerCase() ?? '';
    if (v != fellowship) return false;
  }
  if (f.armId != null && e.partnershipArmId != f.armId) return false;
  if (f.amount != null && !f.amount!.contains(e.amountCedis)) return false;
  if (f.recordedBy != null && e.createdBy != f.recordedBy) return false;
  return true;
}

class RecordFiltersNotifier extends Notifier<RecordFilters> {
  @override
  RecordFilters build() => RecordFilters.empty;

  void set(RecordFilters next) => state = next;
  void clear() => state = RecordFilters.empty;
  void remove(RecordFilterKind kind) => state = state.without(kind);
}

final recordFiltersProvider =
    NotifierProvider<RecordFiltersNotifier, RecordFilters>(
      RecordFiltersNotifier.new,
    );
