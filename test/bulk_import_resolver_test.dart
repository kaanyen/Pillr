import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_models.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_parser.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_resolver.dart';
import 'package:the_pillr/features/partners/domain/partner.dart';
import 'package:the_pillr/features/periods/domain/partnership_period.dart';

void main() {
  group('merged and lookalike partners', () {
    test('a merged member ID follows the merge to the survivor', () {
      final keep = _p('keep', 'Kwame Mensah', memberId: 'ACC001');
      final gone = _p('gone', 'Kwame Mensah', memberId: 'ACC002',
          isActive: false, mergedInto: 'keep');
      final rows = resolveBulkImportRows(
        rawRows: _rows([
          ['2024-02-01', 'Kwame Mensah', 'ACC002', '', 'FC', '40', 'Offerings'],
        ]),
        arms: [_arm()],
        activePeriod: _period(),
        partners: [keep],
        inactivePartners: [gone],
        viewerIsStaff: false,
      );
      expect(rows.single.partnerId, 'keep');
      expect(rows.single.isBlocking, isFalse);
      expect(
        rows.single.issues.map((i) => i.code),
        contains(BulkImportIssueCode.memberIdMerged),
      );
    });

    test('an old ID kept on a merged person finds them', () {
      final merged = Partner(
        id: 'keep', churchId: 'c1', memberId: 'ACC555555', fullName: 'Kwame Mensah',
        fellowship: 'FC', isActive: true, totalApprovedAmount: 0, entryCount: 0,
        createdBy: 'u', createdAt: DateTime(2024), updatedAt: DateTime(2024),
        formerMemberIds: const ['ACC001', 'ACC002'],
      );
      final rows = resolveBulkImportRows(
        rawRows: _rows([
          ['2024-02-01', 'Kwame Mensah', 'acc002', '', 'FC', '40', 'Offerings'],
        ]),
        arms: [_arm()],
        activePeriod: _period(),
        partners: [merged],
        viewerIsStaff: false,
      );
      expect(rows.single.partnerId, 'keep');
      expect(rows.single.isBlocking, isFalse);
      expect(rows.single.issues.single.code, BulkImportIssueCode.memberIdMerged);
    });

    test('an unknown member ID still stops the row', () {
      final rows = resolveBulkImportRows(
        rawRows: _rows([
          ['2024-02-01', 'Kwame Mensah', 'ACC999', '', 'FC', '40', 'Offerings'],
        ]),
        arms: [_arm()],
        activePeriod: _period(),
        partners: [_p('keep', 'Kwame Mensah', memberId: 'ACC001')],
        viewerIsStaff: false,
      );
      expect(rows.single.isBlocking, isTrue);
    });

    test('a new partner that looks like an inactive one is flagged', () {
      final rows = resolveBulkImportRows(
        rawRows: _rows([
          ['2024-02-01', 'Mensah Kwame', '', '+233 24 412 3456', 'FC', '40', 'Offerings'],
        ]),
        arms: [_arm()],
        activePeriod: _period(),
        partners: const [],
        inactivePartners: [
          _p('old', 'Kwame Mensah', memberId: 'ACC001', phone: '0244123456', isActive: false),
        ],
        viewerIsStaff: false,
      );
      expect(rows.single.resolution, PartnerResolutionKind.createNew);
      final issue = rows.single.issues.singleWhere(
        (i) => i.code == BulkImportIssueCode.possibleDuplicatePartner,
      );
      expect(issue.severity, BulkImportSeverity.warning);
      expect(issue.message, contains('ACC001'));
    });

    test('a genuinely new person is not flagged', () {
      final rows = resolveBulkImportRows(
        rawRows: _rows([
          ['2024-02-01', 'Esi Ansah', '', '', 'FC', '40', 'Offerings'],
        ]),
        arms: [_arm()],
        activePeriod: _period(),
        partners: [_p('a', 'Kwame Mensah', memberId: 'ACC001')],
        viewerIsStaff: false,
      );
      expect(
        rows.single.issues.map((i) => i.code),
        isNot(contains(BulkImportIssueCode.possibleDuplicatePartner)),
      );
    });
  });

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

  test('two partners with the same name and fellowship are a pick, not a create', () {
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
      ['2024-01-10', 'Jane Mensah', '', 'Bethel', '', '25', 'Offerings', '', 'NO'],
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
    Partner partner(String id) => Partner(
          id: id,
          churchId: 'c1',
          memberId: id,
          fullName: 'Jane Mensah',
          fellowship: 'Bethel',
          email: null,
          phone: null,
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
      partners: [partner('a'), partner('b')],
      viewerIsStaff: false,
    );

    expect(resolved.single.resolution, PartnerResolutionKind.ambiguous);
    expect(
      resolved.single.issues.map((i) => i.code),
      contains(BulkImportIssueCode.ambiguousName),
    );
    expect(resolved.single.isBlocking, isTrue);
  });

  test('unknown sheet fellowship is a warning with a similar suggestion', () {
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
      [
        '2024-01-10',
        'Jane',
        '0241234567',
        'Fire Felowship',
        '',
        '25',
        'Offerings',
        '',
        'NO',
      ],
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

    final resolved = resolveBulkImportRows(
      rawRows: raw,
      arms: [arm],
      activePeriod: period,
      partners: const [],
      viewerIsStaff: false,
      knownFellowships: const ['Bethel', 'Fire Fellowship'],
    );

    final unknown = resolved.single.issues
        .where((i) => i.code == BulkImportIssueCode.unknownFellowship);
    expect(unknown, isNotEmpty);
    expect(unknown.single.severity, BulkImportSeverity.warning);
    expect(unknown.single.message, 'Fire Fellowship');
    expect(resolved.single.isBlocking, isFalse);
  });

  test('known fellowship spelling is not flagged', () {
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
      [
        '2024-01-10',
        'Jane',
        '0241234567',
        'bethel',
        '',
        '25',
        'Offerings',
        '',
        'NO',
      ],
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

    final resolved = resolveBulkImportRows(
      rawRows: raw,
      arms: [arm],
      activePeriod: period,
      partners: const [],
      viewerIsStaff: false,
      knownFellowships: const ['Bethel'],
    );

    expect(
      resolved.single.issues.map((i) => i.code),
      isNot(contains(BulkImportIssueCode.unknownFellowship)),
    );
  });
}

// ------------------------------------------------- merged and lookalike partners

PartnershipArm _arm() => PartnershipArm(
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

PartnershipPeriod _period() => PartnershipPeriod(
  id: 'p1',
  churchId: 'c1',
  name: '2024',
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

Partner _p(
  String id,
  String name, {
  String memberId = '',
  String? phone,
  bool isActive = true,
  String? mergedInto,
}) => Partner(
  id: id,
  churchId: 'c1',
  memberId: memberId,
  fullName: name,
  fellowship: 'FC',
  phone: phone,
  isActive: isActive,
  totalApprovedAmount: 0,
  entryCount: 0,
  createdBy: 'u',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  mergedInto: mergedInto,
);

List<BulkRawRow> _rows(List<List<String?>> data) => parseBulkImportGrid([
  ['DATE', 'NAME', 'MEMBER ID', 'CONTACT', 'FELLOWSHIP', 'AMOUNT (GHC)', 'CATEGORY'],
  ...data,
]).rows;
