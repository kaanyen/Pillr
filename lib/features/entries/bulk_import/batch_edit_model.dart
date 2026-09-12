/// Editing an import after it has landed.
///
/// The import grid checks a spreadsheet before it becomes anything. This is the
/// other half: the same rows, months later, when one of them turns out to be
/// wrong. By then they are entries — approved money, counted in a partner's
/// total and a period's — so an edit here is not a correction to a draft, it is
/// a correction to the books. Every change is therefore stated before it is
/// saved, and only rows that actually differ are written.
///
/// Deliberately free of Firestore and of Flutter: what changed, and what it
/// adds up to, is arithmetic worth testing on its own.
library;

import '../../../core/utils/money.dart';
import '../domain/partnership_entry.dart';

/// One row of an import, as it was and as someone has edited it.
class BatchRowDraft {
  BatchRowDraft({
    required this.original,
    required this.partnerId,
    required this.partnerName,
    required this.amountCedis,
    required this.dateGiven,
    required this.armId,
    required this.armName,
  });

  /// The row as it stands in the books.
  factory BatchRowDraft.from(PartnershipEntry entry) => BatchRowDraft(
        original: entry,
        partnerId: entry.partnerId,
        partnerName: entry.partnerSnapshot['fullName']?.toString() ?? 'Partner',
        amountCedis: entry.amountCedis,
        dateGiven: entry.dateGiven,
        armId: entry.partnershipArmId,
        armName: entry.armSnapshot['name']?.toString() ?? '',
      );

  final PartnershipEntry original;

  String partnerId;
  String partnerName;
  double amountCedis;
  DateTime dateGiven;
  String armId;
  String armName;

  /// A voided row is settled. Its money has already been taken back out, and
  /// editing it would quietly put some of it back.
  bool get isLocked => original.isVoided;

  bool get amountChanged =>
      toPesewas(amountCedis) != toPesewas(original.amountCedis);

  bool get dateChanged => !_sameDay(dateGiven, original.dateGiven);

  bool get partnerChanged => partnerId != original.partnerId;

  bool get armChanged => armId != original.partnershipArmId;

  bool get hasChanges =>
      !isLocked && (amountChanged || dateChanged || partnerChanged || armChanged);

  /// What moves, in pesewas, if this row is saved. Zero unless the amount
  /// changed — moving a gift to another partner moves the whole amount between
  /// two totals but changes neither the church's nor the period's.
  int get pesewasDelta =>
      amountChanged ? toPesewas(amountCedis) - toPesewas(original.amountCedis) : 0;

  /// Plain-English list of what was touched, for the confirmation.
  List<String> get changes => [
        if (partnerChanged)
          'partner: ${original.partnerSnapshot['fullName'] ?? 'Partner'} → $partnerName',
        if (amountChanged)
          'amount: ${original.amountCedis.toStringAsFixed(2)} → '
              '${amountCedis.toStringAsFixed(2)}',
        if (dateChanged) 'date: ${_d(original.dateGiven)} → ${_d(dateGiven)}',
        if (armChanged)
          'arm: ${original.armSnapshot['name'] ?? ''} → $armName',
      ];

  void reset() {
    partnerId = original.partnerId;
    partnerName = original.partnerSnapshot['fullName']?.toString() ?? 'Partner';
    amountCedis = original.amountCedis;
    dateGiven = original.dateGiven;
    armId = original.partnershipArmId;
    armName = original.armSnapshot['name']?.toString() ?? '';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// What a set of edits comes to, before any of it is written.
class BatchEditSummary {
  const BatchEditSummary({
    required this.changedRows,
    required this.pesewasDelta,
    required this.totalPesewas,
    required this.lockedRows,
  });

  final int changedRows;

  /// How much the batch's approved total moves, in pesewas.
  final int pesewasDelta;

  /// What the batch will add up to after saving — approved rows only, since
  /// those are the only ones counted anywhere.
  final int totalPesewas;

  /// Rows that cannot be edited because they have been voided.
  final int lockedRows;

  bool get hasChanges => changedRows > 0;
  double get amountDelta => fromPesewas(pesewasDelta);
  double get total => fromPesewas(totalPesewas);
}

BatchEditSummary summariseBatchEdits(Iterable<BatchRowDraft> drafts) {
  var changed = 0;
  var delta = 0;
  var total = 0;
  var locked = 0;
  for (final d in drafts) {
    if (d.isLocked) {
      locked++;
      continue;
    }
    if (d.hasChanges) changed++;
    delta += d.pesewasDelta;
    // Only approved money is counted anywhere in the app, so only approved
    // money is what this total can honestly claim to be.
    if (d.original.countsTowardTotals) total += toPesewas(d.amountCedis);
  }
  return BatchEditSummary(
    changedRows: changed,
    pesewasDelta: delta,
    totalPesewas: total,
    lockedRows: locked,
  );
}
