import 'package:equatable/equatable.dart';

import '../../partners/domain/partner.dart';
import 'bulk_import_columns.dart';

enum BulkImportSeverity { error, warning }

enum BulkImportIssueCode {
  missingName,
  missingFellowship,
  missingAmount,
  invalidAmount,
  missingDate,
  invalidDate,
  missingArm,
  armNotFound,
  periodNotFound,
  ambiguousPhone,
  memberIdNotFound,
  memberIdConflict,
  fellowshipMismatch,
  nameMismatch,
  duplicateInFile,
  duplicateInDatabase,
  staffPastorYesPending,
}

class BulkImportIssue extends Equatable {
  const BulkImportIssue({
    required this.code,
    required this.severity,
    this.message,
  });

  final BulkImportIssueCode code;
  final BulkImportSeverity severity;
  final String? message;

  @override
  List<Object?> get props => [code, severity, message];
}

/// One raw row after parsing the sheet (0-based data row index in [grid]).
class BulkRawRow extends Equatable {
  const BulkRawRow({
    required this.sheetRowNumber,
    required this.valuesByColumn,
  });

  /// 1-based Excel row number (for display).
  final int sheetRowNumber;
  final Map<BulkImportColumn, String> valuesByColumn;

  @override
  List<Object?> get props => [sheetRowNumber, valuesByColumn];
}

enum PartnerResolutionKind {
  existing,
  createNew,
  ambiguous,
  unresolved,
}

/// Row after matching arms/periods/partners.
class BulkResolvedRow extends Equatable {
  const BulkResolvedRow({
    required this.sheetRowNumber,
    required this.fullName,
    required this.fellowship,
    required this.phone,
    required this.email,
    required this.memberIdFromSheet,
    required this.amountCedis,
    required this.dateGiven,
    required this.armId,
    required this.armName,
    required this.periodId,
    required this.periodName,
    required this.notes,
    required this.pastorConfirmed,
    required this.resolution,
    required this.partnerId,
    required this.partner,
    required this.issues,
    required this.isBlocking,
  });

  final int sheetRowNumber;
  final String fullName;
  final String fellowship;
  final String phone;
  final String email;
  final String? memberIdFromSheet;
  final double amountCedis;
  final DateTime dateGiven;
  final String? armId;
  final String armName;
  final String? periodId;
  final String periodName;
  final String? notes;
  final bool pastorConfirmed;

  final PartnerResolutionKind resolution;
  final String? partnerId;
  final Partner? partner;

  final List<BulkImportIssue> issues;
  final bool isBlocking;

  BulkResolvedRow copyWith({
    String? fullName,
    String? fellowship,
    String? phone,
    String? email,
    String? memberIdFromSheet,
    double? amountCedis,
    DateTime? dateGiven,
    String? armId,
    String? armName,
    String? periodId,
    String? periodName,
    String? notes,
    bool? pastorConfirmed,
    PartnerResolutionKind? resolution,
    String? partnerId,
    Partner? partner,
    List<BulkImportIssue>? issues,
    bool? isBlocking,
  }) {
    return BulkResolvedRow(
      sheetRowNumber: sheetRowNumber,
      fullName: fullName ?? this.fullName,
      fellowship: fellowship ?? this.fellowship,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      memberIdFromSheet: memberIdFromSheet ?? this.memberIdFromSheet,
      amountCedis: amountCedis ?? this.amountCedis,
      dateGiven: dateGiven ?? this.dateGiven,
      armId: armId ?? this.armId,
      armName: armName ?? this.armName,
      periodId: periodId ?? this.periodId,
      periodName: periodName ?? this.periodName,
      notes: notes ?? this.notes,
      pastorConfirmed: pastorConfirmed ?? this.pastorConfirmed,
      resolution: resolution ?? this.resolution,
      partnerId: partnerId ?? this.partnerId,
      partner: partner ?? this.partner,
      issues: issues ?? this.issues,
      isBlocking: isBlocking ?? this.isBlocking,
    );
  }

  @override
  List<Object?> get props => [
        sheetRowNumber,
        fullName,
        fellowship,
        phone,
        email,
        memberIdFromSheet,
        amountCedis,
        dateGiven,
        armId,
        armName,
        periodId,
        periodName,
        notes,
        pastorConfirmed,
        resolution,
        partnerId,
        partner,
        issues,
        isBlocking,
      ];
}

class BulkImportSummary extends Equatable {
  const BulkImportSummary({
    required this.totalRows,
    required this.newPartners,
    required this.existingPartners,
    required this.totalAmount,
    required this.warningCount,
    required this.blockingCount,
    required this.pastorYesCount,
    required this.staffPastorYesCount,
  });

  final int totalRows;
  final int newPartners;
  final int existingPartners;
  final double totalAmount;
  final int warningCount;
  final int blockingCount;
  final int pastorYesCount;
  final int staffPastorYesCount;

  @override
  List<Object?> get props => [
        totalRows,
        newPartners,
        existingPartners,
        totalAmount,
        warningCount,
        blockingCount,
        pastorYesCount,
        staffPastorYesCount,
      ];
}
