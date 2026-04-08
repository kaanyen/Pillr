import '../../arms/domain/partnership_arm.dart';
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
  required bool viewerIsStaff,
}) {
  final byPhone = <String, List<Partner>>{};
  for (final p in partners) {
    if (!p.isActive) continue;
    final key = normalizePhoneDigits(p.phone);
    if (key.isEmpty) continue;
    byPhone.putIfAbsent(key, () => []).add(p);
  }

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
      Partner? byMember;
      for (final p in partners) {
        if (p.memberId.toUpperCase() == mid.toUpperCase()) {
          byMember = p;
          break;
        }
      }
      if (byMember == null) {
        issues.add(
          const BulkImportIssue(
            code: BulkImportIssueCode.memberIdNotFound,
            severity: BulkImportSeverity.error,
          ),
        );
      } else {
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
          final byName = _singlePartnerByNameAndFellowship(fullName, fellowship, partners);
          if (byName != null) {
            matched = byName;
            resolution = PartnerResolutionKind.existing;
          } else {
            resolution = PartnerResolutionKind.createNew;
          }
        }
      } else {
        final byName = _singlePartnerByNameAndFellowship(fullName, fellowship, partners);
        if (byName != null) {
          matched = byName;
          resolution = PartnerResolutionKind.existing;
        } else {
          resolution = PartnerResolutionKind.createNew;
        }
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

    final blocking = issues.any((i) => i.severity == BulkImportSeverity.error);

    resolved.add(
      BulkResolvedRow(
        sheetRowNumber: raw.sheetRowNumber,
        fullName: fullName,
        fellowship: fellowship,
        phone: phone,
        email: email,
        memberIdFromSheet: memberIdFromSheet,
        amountCedis: interp.amount ?? 0,
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

Partner? _singlePartnerByNameAndFellowship(
  String fullName,
  String fellowship,
  List<Partner> partners,
) {
  final nl = fullName.toLowerCase().trim();
  final fl = fellowship.toLowerCase().trim();
  if (nl.isEmpty || fl.isEmpty) return null;
  Partner? found;
  for (final p in partners) {
    if (!p.isActive) continue;
    if (p.fellowship.toLowerCase().trim() != fl) continue;
    if (p.fullName.toLowerCase().trim() == nl) {
      if (found != null) return null;
      found = p;
    }
  }
  return found;
}

bool _sameArmForInFileDedupe(BulkResolvedRow a, BulkResolvedRow b) {
  if (a.armId != null && b.armId != null && a.armId == b.armId) return true;
  return normalizeArmExcelText(a.armName) == normalizeArmExcelText(b.armName);
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

  for (var i = 0; i < rows.length; i++) {
    final a = rows[i];
    if (a.periodId == null) continue;
    for (var j = 0; j < i; j++) {
      final b = rows[j];
      if (b.periodId == null) continue;
      if (a.periodId != b.periodId) continue;
      if (_partnerDedupeKey(a) != _partnerDedupeKey(b)) continue;
      if (!_sameArmForInFileDedupe(a, b)) continue;
      if (_dateOnly(a.dateGiven) != _dateOnly(b.dateGiven)) continue;
      if (!similarAmount(a.amountCedis, b.amountCedis)) continue;

      void flag(int idx) {
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

      flag(i);
      flag(j);
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
