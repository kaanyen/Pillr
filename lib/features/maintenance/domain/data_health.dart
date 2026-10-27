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

/// How sure the scan is that two records are one person.
enum DuplicateBand {
  /// An identifying field matches: member ID, or phone/email with the name.
  almostCertain,

  /// The name matches, or an identifier does and the name nearly does.
  likely,

  /// Worth a look — a near name, or a shared phone with a different name.
  check,
}

/// Two partner records that look like the same person.
class DuplicatePartnerPair {
  const DuplicatePartnerPair({
    required this.a,
    required this.b,
    required this.reasons,
    required this.confidence,
  });

  final Partner a;
  final Partner b;

  /// Each piece of evidence, in words a pastor can check against the records.
  final List<String> reasons;

  /// 0–1. 1.0 is an exact match on member ID.
  final double confidence;

  String get reason => reasons.join(' · ');

  DuplicateBand get band => confidence >= 0.9
      ? DuplicateBand.almostCertain
      : confidence >= 0.6
      ? DuplicateBand.likely
      : DuplicateBand.check;

  /// Stable id for the pair, whichever way round it was found.
  String get key => duplicatePairKey(a.id, b.id);
}

String duplicatePairKey(String a, String b) => ([a, b]..sort()).join('|');

/// Below this a pair is not reported at all.
const _reportFloor = 0.4;

/// Words that are a form of address, not part of the name.
///
/// "Nana" is deliberately absent: it is a title and also a given name, and
/// stripping it would pair Nana Ama Serwaa with Ama Serwaa as certain. The
/// contained-name rule still offers that pair, as one to check.
const _titles = {
  'mr', 'mrs', 'ms', 'miss', 'mst', 'dr', 'doc', 'prof', 'rev', 'revd',
  'reverend', 'pastor', 'ps', 'pst', 'elder', 'eld', 'deacon', 'dcn',
  'deaconess', 'dcns', 'apostle', 'apst', 'prophet', 'prophetess', 'bishop',
  'evangelist', 'evang', 'sir', 'madam', 'mad', 'hon', 'engr', 'eng', 'lady',
  'bro', 'brother', 'sis', 'sister', 'snr', 'sr', 'jnr', 'jr',
};

/// A name taken apart for comparison.
class _Name {
  _Name(String raw) {
    final words = raw
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    exact = words.join(' ');
    for (final w in words) {
      if (_titles.contains(w)) continue;
      if (w.length == 1) {
        initials.add(w);
      } else {
        core.add(w);
      }
    }
    core.sort();
    joined = core.join(' ');
  }

  late final String exact;
  final core = <String>[];
  final initials = <String>[];
  late final String joined;
}

/// Phone numbers compared by their last nine digits, so `+233 24 412 3456`,
/// `00233244123456` and `0244123456` are one number. Nine is a Ghanaian
/// subscriber number; for longer foreign numbers the last nine are still
/// specific enough inside one church.
String phoneKey(String? raw) {
  final d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  return d.length < 9 ? '' : d.substring(d.length - 9);
}

String emailKey(String? raw) {
  final e = (raw ?? '').trim().toLowerCase();
  return e.contains('@') ? e : '';
}

/// How alike two names are, and how to say so. Null when they are not.
({double weight, String reason})? _nameSignal(_Name x, _Name y) {
  if (x.exact.isEmpty || y.exact.isEmpty) return null;
  if (x.exact == y.exact) return (weight: 0.6, reason: 'Same name');
  if (x.core.isEmpty || y.core.isEmpty) return null;
  if (x.joined == y.joined) {
    return (weight: 0.55, reason: 'Same name, written differently');
  }

  final xs = x.core.toSet();
  final ys = y.core.toSet();
  final shared = xs.intersection(ys);

  // "K. Mensah" and "Kwame Mensah": the rest of the name agrees and the
  // initial stands for the missing word.
  bool initialCovers(_Name short, Set<String> shortSet, Set<String> longSet) {
    if (short.initials.isEmpty || !longSet.containsAll(shortSet)) return false;
    final missing = longSet.difference(shortSet);
    return missing.isNotEmpty &&
        missing.length <= short.initials.length &&
        missing.every((w) => short.initials.contains(w[0]));
  }

  if (shared.isNotEmpty &&
      (initialCovers(x, xs, ys) || initialCovers(y, ys, xs))) {
    return (weight: 0.5, reason: 'Same name, one with an initial');
  }
  if (shared.length >= 2 &&
      (shared.length == xs.length || shared.length == ys.length)) {
    return (weight: 0.45, reason: 'One name contains the other');
  }
  if (x.core.length == y.core.length && x.joined.length >= 6) {
    final sim = textSimilarity(x.joined, y.joined);
    if (sim >= 0.85) return (weight: 0.45, reason: 'Nearly the same name');
  }
  return null;
}

/// 1.0 for identical strings, falling with edit distance.
///
/// Two swapped letters count as one edit, not two — "Asamaoh" for "Asamoah"
/// is the commonest slip at a keyboard.
double textSimilarity(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final m = a.length, n = b.length;
  var prev2 = List<int>.filled(n + 1, 0);
  var prev = List<int>.generate(n + 1, (j) => j);
  var cur = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var best = prev[j] + 1;
      if (cur[j - 1] + 1 < best) best = cur[j - 1] + 1;
      if (prev[j - 1] + cost < best) best = prev[j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) &&
          prev2[j - 2] + 1 < best) {
        best = prev2[j - 2] + 1;
      }
      cur[j] = best;
    }
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  return 1 - prev[n] / (m > n ? m : n);
}

/// Everything known about one partner that the scan compares.
class _Facts {
  _Facts(this.p)
    : name = _Name(p.fullName),
      memberId = p.memberId.trim().toUpperCase(),
      phone = phoneKey(p.phone),
      email = emailKey(p.email),
      fellowship = p.fellowship.trim().toLowerCase();

  final Partner p;
  final _Name name;
  final String memberId;
  final String phone;
  final String email;
  final String fellowship;
}

/// Parsed once per partner object: an import checks every new row against
/// the whole book.
final _factsCache = Expando<_Facts>();
_Facts _factsOf(Partner p) => _factsCache[p] ??= _Facts(p);

/// Scores one pair. Null when there is nothing worth reporting.
///
/// Signals combine as independent evidence (1 − Π(1 − w)), so two moderate
/// signals outrank one. A shared phone or email with an unrelated name is
/// usually a family sharing one, and is scored down to "check"; two records
/// whose phones are both present and different are scored down too.
DuplicatePartnerPair? _score(_Facts x, _Facts y) {
  final reasons = <String>[];
  final weights = <double>[];
  final name = _nameSignal(x.name, y.name);

  if (x.memberId.isNotEmpty && x.memberId == y.memberId) {
    reasons.add('Same member ID (${x.memberId})');
    weights.add(1.0);
  }
  if (x.phone.isNotEmpty && x.phone == y.phone) {
    if (name != null) {
      reasons.add('Same phone number');
      weights.add(0.9);
    } else {
      reasons.add('Same phone number, different names — may be family');
      weights.add(0.45);
    }
  }
  if (x.email.isNotEmpty && x.email == y.email) {
    if (name != null) {
      reasons.add('Same email');
      weights.add(0.9);
    } else {
      reasons.add('Same email, different names — may be family');
      weights.add(0.45);
    }
  }
  if (name != null) {
    reasons.add(name.reason);
    weights.add(name.weight);
  }
  if (weights.isEmpty) return null;

  if (x.fellowship.isNotEmpty && x.fellowship == y.fellowship) {
    reasons.add('Same fellowship');
    weights.add(0.1);
  }

  var miss = 1.0;
  for (final w in weights) {
    miss *= 1 - w;
  }
  var score = 1 - miss;

  final idMatch = x.memberId.isNotEmpty && x.memberId == y.memberId;
  if (!idMatch && x.phone.isNotEmpty && y.phone.isNotEmpty && x.phone != y.phone) {
    reasons.add('Different phone numbers');
    score *= 0.8;
  }
  if (score < _reportFloor) return null;
  return DuplicatePartnerPair(
    a: x.p,
    b: y.p,
    reasons: reasons,
    confidence: score > 1 ? 1 : score,
  );
}

/// Pairs partners that are probably one person, strongest first.
///
/// Inactive partners are included: a duplicate is often the record someone
/// deactivated instead of merging. A record already merged away is not — it
/// would pair with its own survivor forever. Pairs in [dismissed] (see
/// [duplicatePairKey]) were checked by a person and are left out.
///
/// Only records that share something are compared — a member ID, phone,
/// email, a word of the name, or the first or last three letters of one — so
/// a typo still meets its twin without comparing every pair in the book.
List<DuplicatePartnerPair> findDuplicatePartners(
  List<Partner> partners, {
  Set<String> dismissed = const {},
}) {
  final facts = [
    for (final p in partners)
      if ((p.mergedInto ?? '').isEmpty) _factsOf(p),
  ];

  final buckets = <String, List<int>>{};
  void put(String k, int i) => buckets.putIfAbsent(k, () => []).add(i);
  for (var i = 0; i < facts.length; i++) {
    final f = facts[i];
    if (f.memberId.isNotEmpty) put('m:${f.memberId}', i);
    if (f.phone.isNotEmpty) put('p:${f.phone}', i);
    if (f.email.isNotEmpty) put('e:${f.email}', i);
    if (f.name.exact.isNotEmpty) put('n:${f.name.exact}', i);
    for (final w in f.name.core) {
      put('w:$w', i);
      if (w.length >= 4) {
        put('s:${w.substring(0, 3)}', i);
        put('t:${w.substring(w.length - 3)}', i);
      }
    }
  }

  final seen = <String>{};
  final pairs = <DuplicatePartnerPair>[];
  for (final members in buckets.values) {
    if (members.length < 2) continue;
    for (var i = 0; i < members.length; i++) {
      for (var j = i + 1; j < members.length; j++) {
        final x = facts[members[i]];
        final y = facts[members[j]];
        final key = duplicatePairKey(x.p.id, y.p.id);
        if (dismissed.contains(key) || !seen.add(key)) continue;
        final pair = _score(x, y);
        if (pair != null) pairs.add(pair);
      }
    }
  }

  pairs.sort((x, y) => y.confidence.compareTo(x.confidence));
  return pairs;
}

/// Existing partners a new record would duplicate, for a warning before it is
/// saved. Only "likely" or stronger: a near name alone should not interrupt
/// someone entering a new member mid-service.
List<DuplicatePartnerPair> findDuplicatesOf({
  required String fullName,
  String? phone,
  String? email,
  String memberId = '',
  String fellowship = '',
  required List<Partner> existing,
}) {
  final draft = _Facts(
    Partner(
      id: '',
      churchId: '',
      memberId: memberId,
      fullName: fullName,
      fellowship: fellowship,
      phone: phone,
      email: email,
      isActive: true,
      totalApprovedAmount: 0,
      entryCount: 0,
      createdBy: '',
      createdAt: DateTime(2000),
      updatedAt: DateTime(2000),
    ),
  );
  final out = <DuplicatePartnerPair>[];
  for (final p in existing) {
    if ((p.mergedInto ?? '').isNotEmpty) continue;
    final pair = _score(draft, _factsOf(p));
    if (pair != null && pair.band != DuplicateBand.check) out.add(pair);
  }
  out.sort((x, y) => y.confidence.compareTo(x.confidence));
  return out;
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
