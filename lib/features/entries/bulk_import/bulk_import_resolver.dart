import '../../church/domain/exchange_rates.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../fellowships/fellowship_match.dart';
import '../../maintenance/domain/data_health.dart';
import '../../partners/domain/partner.dart';
import '../../periods/domain/partnership_period.dart';
import 'bulk_import_arm_match.dart';
import 'bulk_import_columns.dart';
import 'bulk_import_models.dart';
import 'bulk_import_parser.dart';
import 'bulk_import_phone.dart';

/// Resolves raw rows against church arms, active period, and partner list.
List<BulkResolvedRow> resolveBulkImportRows({
  required List<BulkRawRow> rawRows,
  required List<PartnershipArm> arms,
  required PartnershipPeriod? activePeriod,
  required List<Partner> partners,
  List<Partner> inactivePartners = const [],
  required bool viewerIsStaff,
  ChurchExchangeRates exchangeRates = const ChurchExchangeRates(),
  String defaultImportCurrency = BaseCurrency.code,
  List<String> knownFellowships = const [],
}) {
  final byPhone = <String, List<Partner>>{};
  final byMemberId = <String, Partner>{};
  final byNameFellowship = <String, Partner>{};
  final ambiguousNameFellowship = <String>{};

  for (final p in partners) {
    if (!p.isActive) continue;
    final key = normalizePhoneDigits(p.phone);
    if (key.isNotEmpty) {
      byPhone.putIfAbsent(key, () => []).add(p);
    }
    final mid = p.memberId.trim();
    if (mid.isNotEmpty) {
      byMemberId[mid.toUpperCase()] = p;
    }
    final nl = p.fullName.toLowerCase().trim();
    final fl = p.fellowship.toLowerCase().trim();
    if (nl.isNotEmpty && fl.isNotEmpty) {
      final nk = '$fl|$nl';
      if (byNameFellowship.containsKey(nk)) {
        ambiguousNameFellowship.add(nk);
      } else {
        byNameFellowship[nk] = p;
      }
    }
  }

  // A member ID on a closed record that was merged as a duplicate follows the
  // merge to the partner that took its giving.
  final byId = {for (final p in [...partners, ...inactivePartners]) p.id: p};
  final mergedByMemberId = <String, Partner>{};
  for (final p in inactivePartners) {
    final mid = p.memberId.trim().toUpperCase();
    if (mid.isEmpty || (p.mergedInto ?? '').isEmpty) continue;
    var cur = p;
    for (var hop = 0; hop < 10 && (cur.mergedInto ?? '').isNotEmpty; hop++) {
      final next = byId[cur.mergedInto];
      if (next == null) break;
      cur = next;
    }
    if (cur.isActive && (cur.mergedInto ?? '').isEmpty) {
      mergedByMemberId[mid] = cur;
    }
  }
  final everyone = [...partners, ...inactivePartners];

  final resolved = <BulkResolvedRow>[];

  for (final raw in rawRows) {
    final interp = interpretRawValues(raw);
    final v = raw.valuesByColumn;
    final fullName = v[BulkImportColumn.name]?.trim() ?? '';
    final fellowship = v[BulkImportColumn.fellowship]?.trim() ?? '';
    final phone = v[BulkImportColumn.contact]?.trim() ?? '';
    final email = v[BulkImportColumn.email]?.trim() ?? '';
    final memberIdFromSheet = v[BulkImportColumn.memberId]?.trim();
    final armNameRaw = v[BulkImportColumn.category]?.trim() ?? '';
    final givenTo = v[BulkImportColumn.givenToNotes]?.trim();

    final issues = List<BulkImportIssue>.from(interp.issues);
    if (fellowship.isNotEmpty && knownFellowships.isNotEmpty) {
      final known = mergeKnownFellowships(knownFellowships, const []);
      final exact = known.any((n) => fellowshipNamesMatch(n, fellowship));
      if (!exact) {
        issues.add(
          BulkImportIssue(
            code: BulkImportIssueCode.unknownFellowship,
            severity: BulkImportSeverity.warning,
            message: suggestSimilarFellowship(fellowship, known),
          ),
        );
      }
    }

    final arm = armNameRaw.isEmpty ? null : findArmMatchFromExcelCell(armNameRaw, arms);
    if (armNameRaw.isNotEmpty && arm == null) {
      issues.add(
        const BulkImportIssue(
          code: BulkImportIssueCode.armNotFound,
          severity: BulkImportSeverity.error,
        ),
      );
    }

    if (activePeriod == null) {
      issues.add(
        const BulkImportIssue(
          code: BulkImportIssueCode.periodNotFound,
          severity: BulkImportSeverity.error,
        ),
      );
    }

    Partner? matched;
    var resolution = PartnerResolutionKind.unresolved;

    final mid = memberIdFromSheet;
    if (mid != null && mid.isNotEmpty) {
      final survivor = mergedByMemberId[mid.toUpperCase()];
      final byMember = byMemberId[mid.toUpperCase()] ?? survivor;
      if (byMember == null) {
        issues.add(
          const BulkImportIssue(
            code: BulkImportIssueCode.memberIdNotFound,
            severity: BulkImportSeverity.error,
          ),
        );
      } else {
        if (identical(byMember, survivor)) {
          issues.add(
            BulkImportIssue(
              code: BulkImportIssueCode.memberIdMerged,
              severity: BulkImportSeverity.warning,
              message: '${mid.toUpperCase()} was merged into '
                  '${survivor!.fullName} (${survivor.memberId}).',
            ),
          );
        }
        matched = byMember;
        resolution = PartnerResolutionKind.existing;
        if (fullName.isNotEmpty &&
            byMember.fullName.toLowerCase().trim() != fullName.toLowerCase().trim()) {
          issues.add(
            const BulkImportIssue(
              code: BulkImportIssueCode.nameMismatch,
              severity: BulkImportSeverity.warning,
            ),
          );
        }
        if (fellowship.isNotEmpty &&
            byMember.fellowship.toLowerCase().trim() != fellowship.toLowerCase().trim()) {
          issues.add(
            const BulkImportIssue(
              code: BulkImportIssueCode.fellowshipMismatch,
              severity: BulkImportSeverity.warning,
            ),
          );
        }
        final pDigits = normalizePhoneDigits(byMember.phone);
        final rowDigits = normalizePhoneDigits(phone);
        if (rowDigits.isNotEmpty && pDigits.isNotEmpty && pDigits != rowDigits) {
          issues.add(
            const BulkImportIssue(
              code: BulkImportIssueCode.memberIdConflict,
              severity: BulkImportSeverity.warning,
            ),
          );
        }
      }
    } else {
      final digits = normalizePhoneDigits(phone);
      if (digits.isNotEmpty) {
        final list = byPhone[digits] ?? [];
        if (list.length > 1) {
          issues.add(
            const BulkImportIssue(
              code: BulkImportIssueCode.ambiguousPhone,
              severity: BulkImportSeverity.error,
            ),
          );
          resolution = PartnerResolutionKind.ambiguous;
        } else if (list.length == 1) {
          matched = list.first;
          resolution = PartnerResolutionKind.existing;
          _addNamePhoneWarnings(matched, fullName, fellowship, phone, issues);
        } else {
          final byName = _nameFellowshipMatch(
            fullName,
            fellowship,
            byNameFellowship,
            ambiguousNameFellowship,
          );
          if (byName.ambiguous) {
            issues.add(
              const BulkImportIssue(
                code: BulkImportIssueCode.ambiguousName,
                severity: BulkImportSeverity.error,
              ),
            );
            resolution = PartnerResolutionKind.ambiguous;
          } else if (byName.partner != null) {
            matched = byName.partner;
            resolution = PartnerResolutionKind.existing;
          } else {
            resolution = PartnerResolutionKind.createNew;
          }
        }
      } else {
        final byName = _nameFellowshipMatch(
          fullName,
          fellowship,
          byNameFellowship,
          ambiguousNameFellowship,
        );
        if (byName.ambiguous) {
          issues.add(
            const BulkImportIssue(
              code: BulkImportIssueCode.ambiguousName,
              severity: BulkImportSeverity.error,
            ),
          );
          resolution = PartnerResolutionKind.ambiguous;
        } else if (byName.partner != null) {
          matched = byName.partner;
          resolution = PartnerResolutionKind.existing;
        } else {
          resolution = PartnerResolutionKind.createNew;
        }
      }
    }

    if (resolution == PartnerResolutionKind.createNew && fullName.isNotEmpty) {
      final lookalikes = findDuplicatesOf(
        fullName: fullName,
        phone: phone,
        email: email,
        fellowship: fellowship,
        existing: everyone,
      );
      if (lookalikes.isNotEmpty) {
        final m = lookalikes.first;
        issues.add(
          BulkImportIssue(
            code: BulkImportIssueCode.possibleDuplicatePartner,
            severity: BulkImportSeverity.warning,
            message: 'Looks like ${m.b.fullName}'
                '${m.b.memberId.isEmpty ? '' : ' (${m.b.memberId})'}'
                '${m.b.isActive ? '' : ', inactive'} — ${m.reason}.',
          ),
        );
      }
    }

    if (interp.pastorYes && viewerIsStaff) {
      issues.add(
        const BulkImportIssue(
          code: BulkImportIssueCode.staffPastorYesPending,
          severity: BulkImportSeverity.warning,
        ),
      );
    }

    final notes = givenTo != null && givenTo.isNotEmpty ? givenTo : null;

    final sourceAmount = interp.amount ?? 0;
    final currencyCode = parseCurrencyCode(v[BulkImportColumn.currency]) ??
        interp.amountCurrency ??
        defaultImportCurrency;
    final conversion = exchangeRates.convert(
      sourceAmount: sourceAmount,
      sourceCurrency: currencyCode,
    );
    if (!conversion.rateAvailable) {
      // An error, not a warning: importing at the 1:1 fallback would record
      // every row in this currency at a figure nobody chose.
      issues.add(
        BulkImportIssue(
          code: BulkImportIssueCode.missingExchangeRate,
          severity: BulkImportSeverity.error,
          message: 'No exchange rate is set for '
              '${conversion.sourceCurrency}. Add one in Settings, then import '
              'again.',
        ),
      );
    }

    final blocking = issues.any((i) => i.severity == BulkImportSeverity.error);

    resolved.add(
      BulkResolvedRow(
        sheetRowNumber: raw.sheetRowNumber,
        fullName: fullName,
        fellowship: fellowship,
        phone: phone,
        email: email,
        memberIdFromSheet: memberIdFromSheet,
        amountCedis: conversion.amountBase,
        sourceCurrency: conversion.sourceCurrency,
        sourceAmount: conversion.sourceAmount,
        exchangeRateToBase: conversion.exchangeRateToBase,
        dateGiven: interp.date ?? DateTime.now(),
        armId: arm?.id,
        armName: armNameRaw,
        periodId: activePeriod?.id,
        periodName: activePeriod?.name ?? '',
        notes: notes,
        pastorConfirmed: interp.pastorYes,
        resolution: resolution,
        partnerId: matched?.id,
        partner: matched,
        issues: issues,
        isBlocking: blocking,
      ),
    );
  }

  _applyDuplicateInFile(resolved);

  return resolved;
}

void _addNamePhoneWarnings(
  Partner matched,
  String fullName,
  String fellowship,
  String phone,
  List<BulkImportIssue> issues,
) {
  if (fullName.isNotEmpty &&
      matched.fullName.toLowerCase().trim() != fullName.toLowerCase().trim()) {
    issues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.nameMismatch,
        severity: BulkImportSeverity.warning,
      ),
    );
  }
  if (fellowship.isNotEmpty &&
      matched.fellowship.toLowerCase().trim() != fellowship.toLowerCase().trim()) {
    issues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.fellowshipMismatch,
        severity: BulkImportSeverity.warning,
      ),
    );
  }
}

({Partner? partner, bool ambiguous}) _nameFellowshipMatch(
  String fullName,
  String fellowship,
  Map<String, Partner> byNameFellowship,
  Set<String> ambiguousNameFellowship,
) {
  final nl = fullName.toLowerCase().trim();
  final fl = fellowship.toLowerCase().trim();
  if (nl.isEmpty || fl.isEmpty) return (partner: null, ambiguous: false);
  final key = '$fl|$nl';
  if (ambiguousNameFellowship.contains(key)) {
    return (partner: null, ambiguous: true);
  }
  return (partner: byNameFellowship[key], ambiguous: false);
}

String _partnerDedupeKey(BulkResolvedRow r) {
  if (r.partnerId != null && r.partnerId!.isNotEmpty) return 'id:${r.partnerId}';
  return 'p:${normalizePhoneDigits(r.phone)}|${r.fullName.toLowerCase().trim()}|${r.fellowship.toLowerCase().trim()}';
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

void _applyDuplicateInFile(List<BulkResolvedRow> rows) {
  bool similarAmount(double a, double b) {
    const t = 0.10;
    final lo = b * (1 - t);
    final hi = b * (1 + t);
    return a >= lo && a <= hi;
  }

  String bucketKey(BulkResolvedRow r) {
    if (r.periodId == null) return '';
    return '${r.periodId}|${_partnerDedupeKey(r)}|'
        '${normalizeArmExcelText(r.armName)}|'
        '${_dateOnly(r.dateGiven).millisecondsSinceEpoch}|'
        '${r.amountCedis.toStringAsFixed(2)}';
  }

  final buckets = <String, List<int>>{};
  for (var i = 0; i < rows.length; i++) {
    final key = bucketKey(rows[i]);
    if (key.isEmpty) continue;
    buckets.putIfAbsent(key, () => []).add(i);
  }

  for (final indices in buckets.values) {
    if (indices.length < 2) continue;
    for (final i in indices) {
      final row = rows[i];
      final next = List<BulkImportIssue>.from(row.issues)
        ..add(
          const BulkImportIssue(
            code: BulkImportIssueCode.duplicateInFile,
            severity: BulkImportSeverity.warning,
          ),
        );
      rows[i] = row.copyWith(
        issues: next,
        isBlocking: next.any((e) => e.severity == BulkImportSeverity.error),
      );
    }
  }

  // Near-duplicate amounts within same partner/arm/date still need fuzzy match.
  final fuzzyBuckets = <String, List<int>>{};
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    if (r.periodId == null) continue;
    final key =
        '${r.periodId}|${_partnerDedupeKey(r)}|${normalizeArmExcelText(r.armName)}|'
        '${_dateOnly(r.dateGiven).millisecondsSinceEpoch}';
    fuzzyBuckets.putIfAbsent(key, () => []).add(i);
  }

  for (final indices in fuzzyBuckets.values) {
    if (indices.length < 2) continue;
    for (var a = 0; a < indices.length; a++) {
      for (var b = a + 1; b < indices.length; b++) {
        final i = indices[a];
        final j = indices[b];
        if (!similarAmount(rows[i].amountCedis, rows[j].amountCedis)) continue;
        for (final idx in [i, j]) {
          if (rows[idx].issues.any((x) => x.code == BulkImportIssueCode.duplicateInFile)) {
            continue;
          }
          final row = rows[idx];
          final next = List<BulkImportIssue>.from(row.issues)
            ..add(
              const BulkImportIssue(
                code: BulkImportIssueCode.duplicateInFile,
                severity: BulkImportSeverity.warning,
              ),
            );
          rows[idx] = row.copyWith(
            issues: next,
            isBlocking: next.any((e) => e.severity == BulkImportSeverity.error),
          );
        }
      }
    }
  }
}

BulkImportSummary summarize(List<BulkResolvedRow> rows, {required bool viewerIsStaff}) {
  var newP = 0;
  var existing = 0;
  double total = 0;
  var warnings = 0;
  var blocking = 0;
  var pastorYes = 0;
  var staffYes = 0;

  for (final r in rows) {
    total += r.amountCedis;
    if (r.resolution == PartnerResolutionKind.createNew) newP++;
    if (r.resolution == PartnerResolutionKind.existing) existing++;
    for (final i in r.issues) {
      if (i.severity == BulkImportSeverity.warning) warnings++;
      if (i.severity == BulkImportSeverity.error) blocking++;
    }
    if (r.pastorConfirmed) {
      pastorYes++;
      if (viewerIsStaff) staffYes++;
    }
  }

  return BulkImportSummary(
    totalRows: rows.length,
    newPartners: newP,
    existingPartners: existing,
    totalAmount: total,
    warningCount: warnings,
    blockingCount: blocking,
    pastorYesCount: pastorYes,
    staffPastorYesCount: staffYes,
  );
}
