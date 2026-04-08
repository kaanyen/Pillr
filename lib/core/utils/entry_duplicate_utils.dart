import '../../features/entries/domain/partnership_entry.dart';

/// Build doc §16.4.3 — same partner + arm + period + amount within ±10%.
bool hasSimilarPartnershipEntry(
  List<PartnershipEntry> entries, {
  required String partnerId,
  required String armId,
  required String periodId,
  required double amount,
}) {
  const threshold = 0.10;
  for (final e in entries) {
    if (e.partnerId != partnerId) continue;
    if (e.partnershipArmId != armId) continue;
    if (e.partnershipPeriodId != periodId) continue;
    final lo = e.amountCedis * (1 - threshold);
    final hi = e.amountCedis * (1 + threshold);
    if (amount >= lo && amount <= hi) return true;
  }
  return false;
}
