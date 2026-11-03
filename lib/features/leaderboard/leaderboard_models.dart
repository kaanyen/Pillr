import '../../core/utils/text_case_utils.dart';
import '../../features/arms/domain/arm_tree.dart';
import '../../features/arms/domain/partnership_arm.dart';
import '../entries/domain/partnership_entry.dart';
import '../entries/fellowship_of.dart';

/// Rankings for one partnership arm in the active period.
class ArmLeaderboard {
  const ArmLeaderboard({
    required this.armId,
    required this.armName,
    required this.rows,
  });

  final String armId;
  final String armName;
  final List<LeaderboardRow> rows;

  double get totalCedis =>
      rows.fold<double>(0, (sum, row) => sum + row.totalCedis);

  /// One ranked list per arm, in the church's arm sort order.
  static List<ArmLeaderboard> fromEntriesAndArms(
    List<PartnershipEntry> entries,
    List<PartnershipArm> arms, {
    String? periodId,
    Set<String> Function(String armId)? armFamilyOf,
  }) {
    final tree = ArmTree(arms);
    return [
      // One section per main arm, ranking its sub-arms' giving with its own.
      // Sub-arms are shown only in Configuration.
      for (final arm in tree.mains)
        ArmLeaderboard(
          armId: arm.id,
          armName: arm.name,
          rows: LeaderboardRow.fromEntries(
            entries,
            periodId: periodId,
            armIds: armFamilyOf?.call(arm.id) ?? tree.familyOf(arm.id),
          ),
        ),
    ];
  }
}

/// Rankings for one fellowship group in the active period.
class FellowshipLeaderboard {
  const FellowshipLeaderboard({
    required this.fellowshipKey,
    required this.fellowshipName,
    required this.rows,
  });

  /// Lowercase fellowship token used for matching entry snapshots.
  final String fellowshipKey;
  final String fellowshipName;
  final List<LeaderboardRow> rows;

  double get totalCedis =>
      rows.fold<double>(0, (sum, row) => sum + row.totalCedis);

  /// One ranked list per fellowship that has approved giving in [entries].
  ///
  /// Fellowships are discovered from entry snapshots (not a separate registry),
  /// sorted A–Z with partners who have no fellowship listed last.
  static List<FellowshipLeaderboard> fromEntries(
    List<PartnershipEntry> entries, {
    String? periodId,
    Map<String, String> fellowshipByPartnerId = const {},
  }) {
    final labels = _fellowshipLabels(
      entries,
      periodId: periodId,
      fellowshipByPartnerId: fellowshipByPartnerId,
    );
    final keys = labels.keys.toList()..sort(_fellowshipKeyOrder(labels));

    return [
      for (final key in keys)
        FellowshipLeaderboard(
          fellowshipKey: key,
          fellowshipName: labels[key]!,
          rows: LeaderboardRow.fromEntries(
            entries,
            periodId: periodId,
            fellowshipKey: key,
            fellowshipByPartnerId: fellowshipByPartnerId,
          ),
        ),
    ].where((section) => section.rows.isNotEmpty).toList();
  }
}

/// One fellowship's standing when fellowships are ranked against each other.
class FellowshipRankRow {
  const FellowshipRankRow({
    required this.rank,
    required this.fellowshipKey,
    required this.fellowshipName,
    required this.partnerCount,
    required this.totalCedis,
  });

  final int rank;
  final String fellowshipKey;
  final String fellowshipName;
  final int partnerCount;
  final double totalCedis;

  static List<FellowshipRankRow> fromEntries(
    List<PartnershipEntry> entries, {
    String? periodId,
    Map<String, String> fellowshipByPartnerId = const {},
  }) {
    final sections = FellowshipLeaderboard.fromEntries(
      entries,
      periodId: periodId,
      fellowshipByPartnerId: fellowshipByPartnerId,
    );
    final sorted = [...sections]
      ..sort((a, b) => b.totalCedis.compareTo(a.totalCedis));
    return [
      for (var i = 0; i < sorted.length; i++)
        FellowshipRankRow(
          rank: i + 1,
          fellowshipKey: sorted[i].fellowshipKey,
          fellowshipName: sorted[i].fellowshipName,
          partnerCount: sorted[i].rows.length,
          totalCedis: sorted[i].totalCedis,
        ),
    ];
  }
}

/// Fellowship directory row — partner headcount and period giving.
class FellowshipDirectoryRow {
  const FellowshipDirectoryRow({
    required this.fellowshipKey,
    required this.fellowshipName,
    required this.partnerCount,
    required this.periodTotalCedis,
  });

  final String fellowshipKey;
  final String fellowshipName;
  final int partnerCount;
  final double periodTotalCedis;

  static List<FellowshipDirectoryRow> fromPartnersAndEntries(
    Iterable<String> partnerFellowships,
    List<PartnershipEntry> entries, {
    String? periodId,
    Map<String, String> fellowshipByPartnerId = const {},
    Iterable<String> catalog = const [],
  }) {
    String labelFor(String key, String raw) {
      if (key.isEmpty) return 'No fellowship';
      if (raw.trim().isNotEmpty) return TextCaseUtils.toTitleCase(raw.trim());
      return TextCaseUtils.toTitleCase(key);
    }

    final labels = <String, String>{};
    for (final raw in catalog) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      labels.putIfAbsent(trimmed.toLowerCase(), () => labelFor(trimmed.toLowerCase(), trimmed));
    }
    for (final raw in partnerFellowships) {
      final trimmed = raw.trim();
      final key = trimmed.toLowerCase();
      labels.putIfAbsent(key, () => labelFor(key, trimmed));
    }

    final partnerCounts = <String, int>{};
    for (final raw in partnerFellowships) {
      final key = raw.trim().toLowerCase();
      partnerCounts[key] = (partnerCounts[key] ?? 0) + 1;
    }

    final periodTotals = <String, double>{};
    for (final entry in entries) {
      if (entry.status != 'approved') continue;
      if (periodId != null && entry.partnershipPeriodId != periodId) continue;
      final key = fellowshipKeyOf(entry, fellowshipByPartnerId);
      periodTotals[key] = (periodTotals[key] ?? 0) + entry.amountCedis;
      labels.putIfAbsent(
        key,
        () => fellowshipLabelOf(entry, fellowshipByPartnerId),
      );
    }

    final keys = {...labels.keys, ...periodTotals.keys}.toList()
      ..sort(_fellowshipKeyOrder(labels));

    return [
      for (final key in keys)
        FellowshipDirectoryRow(
          fellowshipKey: key,
          fellowshipName: labels[key] ?? (key.isEmpty ? 'No fellowship' : key),
          partnerCount: partnerCounts[key] ?? 0,
          periodTotalCedis: periodTotals[key] ?? 0,
        ),
    ];
  }
}

class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.partnerId,
    required this.partnerName,
    required this.totalCedis,
  });

  final int rank;
  final String partnerId;
  final String partnerName;
  final double totalCedis;

  static List<LeaderboardRow> fromEntries(
    List<PartnershipEntry> entries, {
    String? periodId,
    String? armId,
    Set<String>? armIds,
    String? fellowshipKey,
    Map<String, String> fellowshipByPartnerId = const {},
  }) {
    final fellowship = fellowshipKey?.toLowerCase();
    final filtered = entries.where((e) {
      if (e.status != 'approved') return false;
      if (periodId != null && e.partnershipPeriodId != periodId) return false;
      if (armId != null && e.partnershipArmId != armId) return false;
      if (armIds != null && !armIds.contains(e.partnershipArmId)) return false;
      if (fellowship != null &&
          fellowshipKeyOf(e, fellowshipByPartnerId) != fellowship) {
        return false;
      }
      return true;
    });
    final sums = <String, double>{};
    final names = <String, String>{};
    for (final e in filtered) {
      sums[e.partnerId] = (sums[e.partnerId] ?? 0) + e.amountCedis;
      names[e.partnerId] = e.partnerSnapshot['fullName']?.toString() ?? 'Partner';
    }
    final sorted = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (var i = 0; i < sorted.length; i++)
        LeaderboardRow(
          rank: i + 1,
          partnerId: sorted[i].key,
          partnerName: names[sorted[i].key] ?? 'Partner',
          totalCedis: sorted[i].value,
        ),
    ];
  }
}

/// A–Z by label, unnamed groups last. Equal keys compare as 0 so `List.sort`
/// does not abort and blank the Fellowships tab.
int Function(String, String) _fellowshipKeyOrder(Map<String, String> labels) {
  return (a, b) {
    if (a == b) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;
    return (labels[a] ?? a).compareTo(labels[b] ?? b);
  };
}

Map<String, String> _fellowshipLabels(
  List<PartnershipEntry> entries, {
  String? periodId,
  Map<String, String> fellowshipByPartnerId = const {},
}) {
  final labels = <String, String>{};
  for (final entry in entries) {
    if (entry.status != 'approved') continue;
    if (periodId != null && entry.partnershipPeriodId != periodId) continue;
    final key = fellowshipKeyOf(entry, fellowshipByPartnerId);
    labels.putIfAbsent(
      key,
      () => fellowshipLabelOf(entry, fellowshipByPartnerId),
    );
  }
  return labels;
}
