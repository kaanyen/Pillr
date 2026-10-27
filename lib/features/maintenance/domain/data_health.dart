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
    this.nameMatch = true,
  });

  /// The names agree. Only these join a [DuplicateGroup]: a family's shared
  /// phone or email must not pull a different person into one.
  final bool nameMatch;

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

/// Akan day names and their common spellings, Twi and Fante, to one key.
///
/// Kofi and Fiifi are the same name; so are Kwaku and Kweku, Ama and Amma.
/// A day name is shared by a seventh of the church, so a match here only
/// counts when the rest of the name agrees too.
const _dayNames = <String, String>{
  // Sunday
  'kwasi': 'sun-m', 'kwesi': 'sun-m', 'akwasi': 'sun-m', 'siisi': 'sun-m',
  'kwasie': 'sun-m', 'akosua': 'sun-f', 'esi': 'sun-f', 'essi': 'sun-f',
  'akos': 'sun-f',
  // Monday
  'kwadwo': 'mon-m', 'kojo': 'mon-m', 'kodwo': 'mon-m', 'jojo': 'mon-m',
  'kwadjo': 'mon-m', 'adwoa': 'mon-f', 'adjoa': 'mon-f', 'adjowa': 'mon-f',
  // Tuesday
  'kwabena': 'tue-m', 'kobina': 'tue-m', 'ebo': 'tue-m', 'kwabina': 'tue-m',
  'kobena': 'tue-m', 'abena': 'tue-f', 'araba': 'tue-f', 'abenaa': 'tue-f',
  // Wednesday
  'kwaku': 'wed-m', 'kweku': 'wed-m', 'kuuku': 'wed-m',
  'kwaaku': 'wed-m', 'akua': 'wed-f', 'ekua': 'wed-f', 'akuah': 'wed-f',
  // Thursday
  'yaw': 'thu-m', 'ekow': 'thu-m', 'yao': 'thu-m', 'kwaw': 'thu-m',
  'yaa': 'thu-f', 'aba': 'thu-f',
  // Friday
  'kofi': 'fri-m', 'fiifi': 'fri-m', 'fifi': 'fri-m', 'fiofi': 'fri-m',
  'afua': 'fri-f', 'efua': 'fri-f', 'afia': 'fri-f', 'afuah': 'fri-f',
  // Saturday
  'kwame': 'sat-m', 'kwamena': 'sat-m', 'kwamina': 'sat-m', 'kwami': 'sat-m',
  'ama': 'sat-f', 'amma': 'sat-f', 'ame': 'sat-f', 'amah': 'sat-f',
};

/// A word reduced to how it sounds rather than how it was typed: doubled
/// letters collapse, a trailing h goes ("Mensah"/"Mensa"), ph is f.
String spellingKey(String word) {
  var w = word.replaceAll('ph', 'f');
  w = w.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  if (w.length > 3 && w.endsWith('h')) w = w.substring(0, w.length - 1);
  return w;
}

String _canonWord(String word) {
  final day = _dayNames[word];
  return day == null ? spellingKey(word) : 'day:$day';
}

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
    canon = [for (final w in core) _canonWord(w)]..sort();
    canonJoined = canon.join(' ');
    spelledJoined = ([for (final w in core) spellingKey(w)]..sort()).join(' ');
  }

  late final String exact;
  final core = <String>[];
  final initials = <String>[];
  late final String joined;

  /// [core] with spelling variants and Akan day names folded together.
  late final List<String> canon;
  late final String canonJoined;

  /// [core] by spelling only. Typos are measured on this: folded day names
  /// are labels, and two labels a letter apart are different names.
  late final String spelledJoined;
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
  if (x.core.length >= 2 && x.canonJoined == y.canonJoined) {
    return (weight: 0.5, reason: 'Same name, another spelling (${_variantNote(x, y)})');
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
    final sim = textSimilarity(x.spelledJoined, y.spelledJoined);
    if (sim >= 0.85) return (weight: 0.45, reason: 'Nearly the same name');
  }

  // "Ella Kabe" and "Emmanuella Catherine Kabe"; "Joy Meyrawo Dziks" and
  // "Joy Meyrawo Dzik-Sewornu": every word of the shorter name is in the
  // longer one, whole, as the start or end of a word, or nearly.
  final shorter = x.core.length <= y.core.length ? x : y;
  final longer = identical(shorter, x) ? y : x;
  if (shorter.core.length >= 2) {
    var exact = 0;
    final allFit = shorter.core.every((w) {
      final cw = _canonWord(w);
      for (final v in longer.core) {
        if (v == w || _canonWord(v) == cw) {
          exact++;
          return true;
        }
      }
      return longer.core.any((v) =>
          (w.length >= 3 && (v.startsWith(w) || v.endsWith(w))) ||
          (v.length >= 3 && (w.startsWith(v) || w.endsWith(v))) ||
          textSimilarity(spellingKey(w), spellingKey(v)) >= 0.8);
    });
    if (allFit && exact >= 1) {
      return (weight: 0.4, reason: 'Short form of the same name');
    }
  }
  return null;
}

/// "Kofi = Fiifi" — the words that differ between two names that fold to
/// the same canonical form.
String _variantNote(_Name x, _Name y) {
  final xs = x.core.toSet().difference(y.core.toSet()).toList()..sort();
  final ys = y.core.toSet().difference(x.core.toSet()).toList()..sort();
  String cap(String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);
  return '${xs.map(cap).join(' ')} = ${ys.map(cap).join(' ')}';
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
      phones = {
        for (final x in p.allPhones)
          if (phoneKey(x).isNotEmpty) phoneKey(x),
      },
      emails = {
        for (final x in p.allEmails)
          if (emailKey(x).isNotEmpty) emailKey(x),
      },
      fellowship = p.fellowship.trim().toLowerCase();

  final Partner p;
  final _Name name;
  final String memberId;
  /// Every phone and email the record holds — a merged person has several.
  final Set<String> phones;
  final Set<String> emails;
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
  // A shared phone or email confirms a name that already agrees. Behind only
  // a short form it is weaker: sisters share numbers.
  final contact = name == null ? 0.0 : (name.weight >= 0.45 ? 0.9 : 0.7);
  if (x.phones.intersection(y.phones).isNotEmpty) {
    if (name != null) {
      reasons.add('Same phone number');
      weights.add(contact);
    } else {
      reasons.add('Same phone number, different names — may be family');
      weights.add(0.45);
    }
  }
  if (x.emails.intersection(y.emails).isNotEmpty) {
    if (name != null) {
      reasons.add('Same email');
      weights.add(contact);
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
  if (!idMatch &&
      x.phones.isNotEmpty &&
      y.phones.isNotEmpty &&
      x.phones.intersection(y.phones).isEmpty) {
    reasons.add('Different phone numbers');
    // The full name in the same fellowship outweighs a phone typed twice
    // differently — the usual way an import makes a second record.
    final sameFullName = name?.reason == 'Same name' && x.name.core.length >= 2;
    final sameGroup = x.fellowship.isNotEmpty && x.fellowship == y.fellowship;
    score *= sameFullName && sameGroup ? 0.9 : 0.8;
  }
  if (score < _reportFloor) return null;
  return DuplicatePartnerPair(
    a: x.p,
    b: y.p,
    reasons: reasons,
    confidence: score > 1 ? 1 : score,
    nameMatch: name != null,
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

  // Sets, not lists: "Boakye Boateng" files the same partner under "boa"
  // twice, and a list would then pair that partner with itself.
  final buckets = <String, Set<int>>{};
  void put(String k, int i) => buckets.putIfAbsent(k, () => {}).add(i);
  for (var i = 0; i < facts.length; i++) {
    final f = facts[i];
    if (f.memberId.isNotEmpty) put('m:${f.memberId}', i);
    for (final ph in f.phones) {
      put('p:$ph', i);
    }
    for (final em in f.emails) {
      put('e:$em', i);
    }
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
  for (final bucket in buckets.values) {
    if (bucket.length < 2) continue;
    final members = bucket.toList();
    for (var i = 0; i < members.length; i++) {
      for (var j = i + 1; j < members.length; j++) {
        final x = facts[members[i]];
        final y = facts[members[j]];
        if (x.p.id == y.p.id) continue;
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

/// Three or more records that are one person, entered again at each import.
class DuplicateGroup {
  const DuplicateGroup({required this.partners, required this.pairs});

  /// Most gifts first, then oldest: the first is the suggested one to keep.
  final List<Partner> partners;

  /// The pairs that link them, for the reasons shown.
  final List<DuplicatePartnerPair> pairs;

  double get confidence =>
      pairs.map((p) => p.confidence).fold(0.0, (a, b) => a > b ? a : b);

  String get key => 'group:${([for (final p in partners) p.id]..sort()).join('|')}';
}

/// Splits [pairs] into groups of three or more and the pairs left over.
///
/// Records join a group through "likely" or stronger pairs whose names agree.
/// Merging a group is one change with one new member ID, instead of a chain
/// of pairwise merges that would hand out an ID at every step.
({List<DuplicateGroup> groups, List<DuplicatePartnerPair> pairs})
groupDuplicates(List<DuplicatePartnerPair> pairs) {
  final parent = <String, String>{};
  String find(String k) {
    var r = parent[k] ?? k;
    while (r != (parent[r] ?? r)) {
      r = parent[r] ?? r;
    }
    parent[k] = r;
    return r;
  }

  bool joins(DuplicatePartnerPair p) => p.nameMatch && p.band != DuplicateBand.check;
  final byId = <String, Partner>{};
  for (final p in pairs) {
    byId[p.a.id] = p.a;
    byId[p.b.id] = p.b;
    if (joins(p)) parent[find(p.a.id)] = find(p.b.id);
  }
  final members = <String, Set<String>>{};
  for (final p in pairs) {
    if (!joins(p)) continue;
    members.putIfAbsent(find(p.a.id), () => {})
      ..add(p.a.id)
      ..add(p.b.id);
  }
  final groups = <DuplicateGroup>[];
  final grouped = <String>{};
  for (final ids in members.values) {
    if (ids.length < 3) continue;
    grouped.addAll(ids);
    final list = [for (final id in ids) byId[id]!]
      ..sort((x, y) {
        final c = y.entryCount.compareTo(x.entryCount);
        return c != 0 ? c : x.createdAt.compareTo(y.createdAt);
      });
    groups.add(DuplicateGroup(
      partners: list,
      pairs: [for (final p in pairs) if (ids.contains(p.a.id) && ids.contains(p.b.id)) p],
    ));
  }
  groups.sort((x, y) => y.partners.length.compareTo(x.partners.length));
  return (
    groups: groups,
    pairs: [
      for (final p in pairs)
        if (!(grouped.contains(p.a.id) && grouped.contains(p.b.id))) p,
    ],
  );
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

/// A partner the person may have meant while searching.
class PartnerSuggestion {
  const PartnerSuggestion({
    required this.partner,
    required this.reason,
    required this.score,
  });

  final Partner partner;
  final String reason;
  final double score;
}

/// "Did you mean…?" for the partner picker.
///
/// The picker's search is a prefix match, so "Mensah Kwame", "Kweku" for
/// Kwaku, or one wrong letter finds nobody — and that is the moment someone
/// creates a second record. This looks across the whole book for names that
/// read the same, spellings and day-name variants included, and for a typed
/// phone number in any format. [exclude] is the ids the search already shows.
List<PartnerSuggestion> suggestPartners(
  String query,
  List<Partner> partners, {
  Set<String> exclude = const {},
  int limit = 5,
}) {
  final q = query.trim();
  if (q.length < 3) return const [];
  final out = <PartnerSuggestion>[];

  final digits = q.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 7 && digits.length * 2 >= q.length) {
    final tail = digits.length > 9 ? digits.substring(digits.length - 9) : digits;
    for (final p in partners) {
      if (exclude.contains(p.id) || (p.mergedInto ?? '').isNotEmpty) continue;
      final match = p.allPhones.any((ph) {
        final pd = ph.replaceAll(RegExp(r'\D'), '');
        return pd.length >= 7 && pd.endsWith(tail);
      });
      if (match) {
        out.add(PartnerSuggestion(partner: p, reason: 'Same phone number', score: 0.95));
      }
    }
  } else {
    final qn = _Name(q);
    if (qn.core.isEmpty) return const [];
    for (final p in partners) {
      if (exclude.contains(p.id) || (p.mergedInto ?? '').isNotEmpty) continue;
      final pn = _factsOf(p).name;
      final sig = _nameSignal(qn, pn);
      if (sig != null) {
        out.add(PartnerSuggestion(partner: p, reason: sig.reason, score: sig.weight));
        continue;
      }
      // Every word typed is close to a word of theirs: a typo, another
      // spelling, a day-name variant, or the start of a longer word.
      var total = 0.0;
      var allClose = true;
      for (final w in qn.core) {
        final cw = _canonWord(w);
        var best = 0.0;
        for (var i = 0; i < pn.core.length; i++) {
          final pw = pn.core[i];
          final pc = _canonWord(pw);
          final sim = cw == pc
              ? 1.0
              : (w.length >= 3 && pw.startsWith(w))
              ? 0.9
              : textSimilarity(cw, pc);
          if (sim > best) best = sim;
        }
        if (best < 0.8) {
          allClose = false;
          break;
        }
        total += best;
      }
      if (allClose) {
        out.add(PartnerSuggestion(
          partner: p,
          reason: 'Similar spelling',
          score: 0.3 * total / qn.core.length,
        ));
      }
    }
  }

  out.sort((a, b) => b.score.compareTo(a.score));
  return out.take(limit).toList();
}
