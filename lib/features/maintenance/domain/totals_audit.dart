/// Recomputes what a total *should* be, straight from the entries.
///
/// Partner, period and goal totals are maintained by Firestore triggers
/// (`syncEntryAggregates`). That pipeline is transactional and idempotent, and
/// it is tested — but a trigger can still fail to fire: a deploy mid-write, a
/// timeout, a document written by a script that bypassed the app. When that
/// happens nothing in the system notices, and the number a pastor reads is
/// quietly wrong from then on.
///
/// This is the check that notices. It is deliberately pure: give it the
/// entries and the stored totals, and it tells you where they disagree. The
/// repair step is a separate decision.
library;

import '../../../core/utils/money.dart';
import '../../entries/domain/partnership_entry.dart';


/// One total that does not match the entries behind it.
class TotalsDrift {
  const TotalsDrift({
    required this.kind,
    required this.id,
    required this.name,
    required this.stored,
    required this.expected,
    required this.storedCount,
    required this.expectedCount,
  });

  final TotalsDriftKind kind;
  final String id;
  final String name;

  /// What the document currently claims.
  final double stored;
  final int storedCount;

  /// What the approved entries actually add up to.
  final double expected;
  final int expectedCount;

  double get amountDelta => fromPesewas(expectedPesewas - storedPesewas);
  int get countDelta => expectedCount - storedCount;

  int get storedPesewas => toPesewas(stored);
  int get expectedPesewas => toPesewas(expected);

  /// Compared as whole pesewas, which is how the trigger counts. Comparing the
  /// cedi doubles needed a tolerance to absorb their own rounding error, and a
  /// tolerance is a place for a real discrepancy to hide.
  bool get amountWrong => storedPesewas != expectedPesewas;
  bool get countWrong => countDelta != 0;
}

enum TotalsDriftKind { partner, period, goal }

/// A stored total, as read off a partner or period document.
class StoredTotal {
  const StoredTotal({
    required this.id,
    required this.name,
    required this.totalApprovedAmount,
    required this.entryCount,
  });

  final String id;
  final String name;
  final double totalApprovedAmount;
  final int entryCount;
}

/// What the entries say each partner and period should hold.
class ExpectedTotals {
  const ExpectedTotals({required this.pesewas, required this.counts});

  /// Whole pesewas per id — the unit the totals are kept in.
  final Map<String, int> pesewas;
  final Map<String, int> counts;

  Iterable<String> get ids => pesewas.keys;

  int pesewasFor(String id) => pesewas[id] ?? 0;
  double amountFor(String id) => fromPesewas(pesewasFor(id));
  int countFor(String id) => counts[id] ?? 0;
}

/// Sums approved entries by [keyOf].
///
/// Only `approved` counts — the same rule the trigger applies, and the same
/// rule every ranking in the app applies. Pending money has not been counted,
/// declined money was refused, and voided money was taken back out.
ExpectedTotals expectedTotalsBy(
  List<PartnershipEntry> entries,
  String Function(PartnershipEntry) keyOf,
) {
  final pesewas = <String, int>{};
  final counts = <String, int>{};
  for (final e in entries) {
    if (!e.countsTowardTotals) continue;
    final key = keyOf(e);
    if (key.isEmpty) continue;
    // Each entry contributes a whole number of pesewas, rounded exactly as the
    // trigger rounds it, so the recount and the running total can agree to the
    // pesewa instead of to within a tolerance.
    pesewas[key] = (pesewas[key] ?? 0) + toPesewas(e.amountCedis);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return ExpectedTotals(pesewas: pesewas, counts: counts);
}

/// Compares stored totals against what the entries add up to.
///
/// Reports a row per disagreement, including documents whose total should be
/// zero but is not — a partner whose only gift was voided still holds the old
/// figure until something puts it back to nothing, and that is exactly the
/// case a naive "recompute what's there" pass would miss.
List<TotalsDrift> findTotalsDrift({
  required TotalsDriftKind kind,
  required List<StoredTotal> stored,
  required ExpectedTotals expected,
}) {
  final out = <TotalsDrift>[];
  final seen = <String>{};

  for (final s in stored) {
    seen.add(s.id);
    final drift = TotalsDrift(
      kind: kind,
      id: s.id,
      name: s.name,
      stored: s.totalApprovedAmount,
      storedCount: s.entryCount,
      expected: expected.amountFor(s.id),
      expectedCount: expected.countFor(s.id),
    );
    if (drift.amountWrong || drift.countWrong) out.add(drift);
  }

  // Entries pointing at something with no stored total at all — an orphan.
  for (final id in expected.ids) {
    if (seen.contains(id)) continue;
    out.add(
      TotalsDrift(
        kind: kind,
        id: id,
        name: '(missing record)',
        stored: 0,
        storedCount: 0,
        expected: expected.amountFor(id),
        expectedCount: expected.countFor(id),
      ),
    );
  }

  out.sort((a, b) => b.amountDelta.abs().compareTo(a.amountDelta.abs()));
  return out;
}

/// A whole-church health summary.
class TotalsAuditReport {
  const TotalsAuditReport({
    required this.partnerDrift,
    required this.periodDrift,
    required this.entriesScanned,
  });

  final List<TotalsDrift> partnerDrift;
  final List<TotalsDrift> periodDrift;
  final int entriesScanned;

  int get issueCount => partnerDrift.length + periodDrift.length;
  bool get isHealthy => issueCount == 0;

  /// The largest single discrepancy, for a one-line summary.
  double get worstDelta {
    var worst = 0.0;
    for (final d in [...partnerDrift, ...periodDrift]) {
      if (d.amountDelta.abs() > worst.abs()) worst = d.amountDelta;
    }
    return worst;
  }
}
