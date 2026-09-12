/// Finds the things that go wrong in a giving ledger over time.
///
/// All pure. Each detector takes what it needs and returns candidates — it
/// never decides anything. Merging two partners or clearing a gift is a
/// judgement about real people's records, so every one of these is a proposal
/// for someone to confirm, not a fix to apply.
library;

import '../../entries/domain/partnership_entry.dart';
import '../../partners/domain/partner.dart';
import '../../../core/utils/text_case_utils.dart';


// ---------------------------------------------------------------- duplicates

/// Two partner records that look like the same person.
class DuplicatePartnerPair {
  const DuplicatePartnerPair({
    required this.a,
    required this.b,
    required this.reason,
    required this.confidence,
  });

  final Partner a;
  final Partner b;

  /// Why these were paired, in words a pastor can check against the records.
  final String reason;

  /// 1.0 is an exact match on an identifying field; lower is a name heuristic.
  final double confidence;
}

String _nameKey(String raw) => TextCaseUtils.toTitleCase(raw).toLowerCase().trim();

String _digits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// Pairs partners that are probably one person.
///
/// Three signals, strongest first: the same member ID, the same phone number,
/// and the same name. Name alone is the weakest — churches genuinely contain
/// two people called Kwame Mensah — so it is reported at lower confidence and
/// never presented as certain.
///
/// Inactive partners are included: a duplicate is often the record someone
/// deactivated instead of merging.
List<DuplicatePartnerPair> findDuplicatePartners(List<Partner> partners) {
  final pairs = <DuplicatePartnerPair>[];
  final seen = <String>{};

  void pair(Partner a, Partner b, String reason, double confidence) {
    final key = ([a.id, b.id]..sort()).join('|');
    if (!seen.add(key)) return;
    pairs.add(
      DuplicatePartnerPair(a: a, b: b, reason: reason, confidence: confidence),
    );
  }

  void group<T>(
    T Function(Partner) keyOf,
    bool Function(T) usable,
    String Function(T) describe,
    double confidence,
  ) {
    final buckets = <T, List<Partner>>{};
    for (final p in partners) {
      final k = keyOf(p);
      if (!usable(k)) continue;
      buckets.putIfAbsent(k, () => []).add(p);
    }
    for (final entry in buckets.entries) {
      final list = entry.value;
      if (list.length < 2) continue;
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          pair(list[i], list[j], describe(entry.key), confidence);
        }
      }
    }
  }

  group<String>(
    (p) => p.memberId.trim().toUpperCase(),
    (k) => k.isNotEmpty,
    (k) => 'Same member ID ($k)',
    1.0,
  );
  group<String>(
    (p) => _digits(p.phone ?? ''),
    // Guard against short or partial numbers pairing unrelated people.
    (k) => k.length >= 9,
    (k) => 'Same phone number',
    0.9,
  );
  group<String>(
    (p) => _nameKey(p.fullName),
    (k) => k.isNotEmpty,
    (k) => 'Same name',
    0.6,
  );

  pairs.sort((x, y) => y.confidence.compareTo(x.confidence));
  return pairs;
}

/// What merging two partners would do, worked out before anything is written.
///
/// The surviving record keeps its own id — every entry already points at it —
/// and absorbs the other's entries. Totals are **recomputed from the entries**
/// rather than added together: the two stored figures may each be wrong, and
/// summing two wrong numbers gives a third wrong number.
class PartnerMergePlan {
  const PartnerMergePlan({
    required this.keep,
    required this.absorb,
    required this.entriesToMove,
    required this.resultingTotal,
    required this.resultingCount,
  });

  final Partner keep;
  final Partner absorb;
  final List<PartnershipEntry> entriesToMove;
  final double resultingTotal;
  final int resultingCount;
}

/// Works out a merge without performing it.
///
/// [allEntries] must contain every entry for both partners.
PartnerMergePlan planPartnerMerge({
  required Partner keep,
  required Partner absorb,
  required List<PartnershipEntry> allEntries,
}) {
  final mine = allEntries
      .where((e) => e.partnerId == keep.id || e.partnerId == absorb.id)
      .toList();

  var total = 0.0;
  var count = 0;
  for (final e in mine) {
    if (!e.countsTowardTotals) continue;
    total += e.amountCedis;
    count++;
  }

  return PartnerMergePlan(
    keep: keep,
    absorb: absorb,
    entriesToMove: mine.where((e) => e.partnerId == absorb.id).toList(),
    resultingTotal: total,
    resultingCount: count,
  );
}

// ----------------------------------------------------------- duplicate gifts

/// The same gift, recorded twice.
class DuplicateEntryPair {
  const DuplicateEntryPair({
    required this.original,
    required this.duplicate,
    required this.reason,
  });

  /// The earlier of the two, by creation. Kept by default.
  final PartnershipEntry original;
  final PartnershipEntry duplicate;
  final String reason;
}

/// Finds gifts recorded more than once.
///
/// The importer catches these at import time; nothing catches the ones typed in
/// by hand, or created by two staff members recording the same envelope. Match
/// is on partner, arm, period, calendar date and amount — the same shape the
/// importer's own duplicate check uses.
///
/// Voided entries are ignored: a voided row is already the resolution of a
/// duplicate, and offering to clear it again would be noise.
List<DuplicateEntryPair> findDuplicateEntries(List<PartnershipEntry> entries) {
  final buckets = <String, List<PartnershipEntry>>{};
  for (final e in entries) {
    if (e.isVoided) continue;
    final day = DateTime(e.dateGiven.year, e.dateGiven.month, e.dateGiven.day);
    final key = [
      e.partnerId,
      e.partnershipArmId,
      e.partnershipPeriodId,
      day.toIso8601String(),
      e.amountCedis.toStringAsFixed(2),
    ].join('|');
    buckets.putIfAbsent(key, () => []).add(e);
  }

  final out = <DuplicateEntryPair>[];
  for (final group in buckets.values) {
    if (group.length < 2) continue;
    final ordered = [...group]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final original = ordered.first;
    for (final dup in ordered.skip(1)) {
      out.add(
        DuplicateEntryPair(
          original: original,
          duplicate: dup,
          reason: 'Same partner, arm, period, date and amount',
        ),
      );
    }
  }

  out.sort((a, b) => b.duplicate.createdAt.compareTo(a.duplicate.createdAt));
  return out;
}

// -------------------------------------------------------------- partner data

enum PartnerIssueKind {
  /// Name or fellowship is not in the app's title case.
  casing,

  /// No member ID — the field every other system keys on.
  missingMemberId,

  /// No fellowship, so the partner is absent from every fellowship ranking.
  missingFellowship,

  /// Two partners hold the same member ID, which should be unique.
  duplicateMemberId,
}

class PartnerDataIssue {
  const PartnerDataIssue({
    required this.partner,
    required this.kind,
    required this.detail,
    this.suggestedFullName,
    this.suggestedFellowship,
  });

  final Partner partner;
  final PartnerIssueKind kind;
  final String detail;

  /// Present only for [PartnerIssueKind.casing] — what the fix would write.
  final String? suggestedFullName;
  final String? suggestedFellowship;

  bool get isAutoFixable => kind == PartnerIssueKind.casing;
}

/// Audits the partner list for the problems that accumulate in it.
///
/// Casing issues are the residue of records created before the normalizing
/// Cloud Function existed, or written by a script that bypassed it. Those are
/// safe to fix in bulk. The rest are reported for a person to deal with,
/// because filling in a member ID or a fellowship is a decision, not a repair.
List<PartnerDataIssue> findPartnerDataIssues(List<Partner> partners) {
  final out = <PartnerDataIssue>[];

  final byMemberId = <String, List<Partner>>{};
  for (final p in partners) {
    final id = p.memberId.trim().toUpperCase();
    if (id.isNotEmpty) byMemberId.putIfAbsent(id, () => []).add(p);
  }

  for (final p in partners) {
    final properName = TextCaseUtils.toTitleCase(p.fullName);
    final properFellowship = TextCaseUtils.toTitleCase(p.fellowship);
    final nameOff = properName != p.fullName.trim() && p.fullName.trim().isNotEmpty;
    final fellowshipOff =
        properFellowship != p.fellowship.trim() && p.fellowship.trim().isNotEmpty;

    if (nameOff || fellowshipOff) {
      out.add(
        PartnerDataIssue(
          partner: p,
          kind: PartnerIssueKind.casing,
          detail: nameOff
              ? '“${p.fullName}” → “$properName”'
              : '“${p.fellowship}” → “$properFellowship”',
          suggestedFullName: nameOff ? properName : null,
          suggestedFellowship: fellowshipOff ? properFellowship : null,
        ),
      );
    }

    if (p.memberId.trim().isEmpty) {
      out.add(
        PartnerDataIssue(
          partner: p,
          kind: PartnerIssueKind.missingMemberId,
          detail: 'No member ID',
        ),
      );
    }

    if (p.fellowship.trim().isEmpty) {
      out.add(
        PartnerDataIssue(
          partner: p,
          kind: PartnerIssueKind.missingFellowship,
          detail: 'Not in a fellowship — excluded from fellowship rankings',
        ),
      );
    }
  }

  for (final entry in byMemberId.entries) {
    if (entry.value.length < 2) continue;
    for (final p in entry.value) {
      out.add(
        PartnerDataIssue(
          partner: p,
          kind: PartnerIssueKind.duplicateMemberId,
          detail: 'Member ID ${entry.key} is used by ${entry.value.length} partners',
        ),
      );
    }
  }

  return out;
}
