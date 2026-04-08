import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_models.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_parser.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_resolver.dart';
import 'package:the_pillr/features/partners/domain/partner.dart';
import 'package:the_pillr/features/periods/domain/partnership_period.dart';

void main() {
  test('resolveBulkImportRows matches partner by phone', () {
    final grid = <List<String?>>[
      [
        'DATE',
        'NAME',
        'CONTACT',
        'FELLOWSHIP',
        'EMAIL',
        'AMOUNT (GHC)',
        'CATEGORY',
        'NOTES',
        'CURRENTLY WITH PASTOR (YES OR NO)',
      ],
      ['2024-01-10', 'Jane', '0241234567', 'FC', '', '25', 'Offerings', '', 'NO'],
    ];
    final raw = parseBulkImportGrid(grid).rows;

    final arm = PartnershipArm(
      id: 'arm1',
      churchId: 'c1',
      name: 'Offerings',
      description: null,
      isActive: true,
      colorHex: null,
      sortOrder: 0,
      createdBy: 'u',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

    final period = PartnershipPeriod(
      id: 'p1',
      churchId: 'c1',
      name: '2024 Q1',
      description: null,
      startDate: DateTime(2024, 1, 1),
      endDate: DateTime(2024, 12, 31),
      isActive: true,
      totalApprovedAmount: 0,
      entryCount: 0,
      createdBy: 'u',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

    final existing = Partner(
      id: 'pid1',
      churchId: 'c1',
      memberId: 'XX100001',
      fullName: 'Jane',
      fellowship: 'FC',
      email: null,
      phone: '0241234567',
      isActive: true,
      totalApprovedAmount: 0,
      entryCount: 0,
      createdBy: 'u',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

    final resolved = resolveBulkImportRows(
      rawRows: raw,
      arms: [arm],
      activePeriod: period,
      partners: [existing],
      viewerIsStaff: false,
    );

    expect(resolved.length, 1);
    expect(resolved.single.resolution, PartnerResolutionKind.existing);
    expect(resolved.single.partnerId, 'pid1');
    expect(resolved.single.isBlocking, isFalse);
  });

  test('resolveBulkImportRows flags duplicate rows in file', () {
    final grid = <List<String?>>[
      [
        'DATE',
        'NAME',
        'CONTACT',
        'FELLOWSHIP',
        'EMAIL',
        'AMOUNT (GHC)',
        'CATEGORY',
        'NOTES',
        'CURRENTLY WITH PASTOR (YES OR NO)',
      ],
      ['2024-01-10', 'Jane', '0241234567', 'FC', '', '100', 'Offerings', '', 'NO'],
      ['2024-01-10', 'Jane', '0241234567', 'FC', '', '101', 'Offerings', '', 'NO'],
    ];
    final raw = parseBulkImportGrid(grid).rows;

    final arm = PartnershipArm(
      id: 'arm1',
      churchId: 'c1',
      name: 'Offerings',
      description: null,
      isActive: true,
      colorHex: null,
      sortOrder: 0,
      createdBy: 'u',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

    final period = PartnershipPeriod(
      id: 'p1',
      churchId: 'c1',
      name: '2024 Q1',
      description: null,
      startDate: DateTime(2024, 1, 1),
      endDate: DateTime(2024, 12, 31),
      isActive: true,
      totalApprovedAmount: 0,
      entryCount: 0,
      createdBy: 'u',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

    final existing = Partner(
      id: 'pid1',
      churchId: 'c1',
      memberId: 'XX100001',
      fullName: 'Jane',
      fellowship: 'FC',
      email: null,
      phone: '0241234567',
      isActive: true,
      totalApprovedAmount: 0,
      entryCount: 0,
      createdBy: 'u',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

    final resolved = resolveBulkImportRows(
      rawRows: raw,
      arms: [arm],
      activePeriod: period,
      partners: [existing],
      viewerIsStaff: false,
    );

    expect(resolved.length, 2);
    final dup = resolved.expand((r) => r.issues).where((i) => i.code == BulkImportIssueCode.duplicateInFile);
    expect(dup.length, greaterThanOrEqualTo(2));
  });
}
