import '../entries/domain/partnership_entry.dart';

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
  }) {
    final filtered = entries.where((e) {
      if (e.status != 'approved') return false;
      if (periodId != null && e.partnershipPeriodId != periodId) return false;
      if (armId != null && e.partnershipArmId != armId) return false;
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
