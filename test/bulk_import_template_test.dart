import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_sources.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_template.dart';

PartnershipArm arm(String id, String name, {bool active = true}) => PartnershipArm(
      id: id, churchId: 'c', name: name, description: null,
      isActive: active, colorHex: null, sortOrder: 0,
      createdBy: 'u', createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

void main() {
  final arms = [
    arm('1', 'Missions'),
    arm('2', 'Church Building'),
    arm('3', 'Retired Arm', active: false),
  ];

  test('the template round-trips through the importer\'s own CSV parser', () {
    final csv = buildImportTemplateCsv(arms: arms, exampleDate: DateTime(2026, 3, 4));
    final grid = parseCsvGrid(csv);
    expect(grid.first, templateHeaders);
    // Row 2 is the example row, aligned to the headers.
    expect(grid[1].length, templateHeaders.length);
    expect(grid[1][1], 'Ama Boateng');
  });

  test('uses an ISO date in the example so the format is unambiguous', () {
    final csv = buildImportTemplateCsv(arms: arms, exampleDate: DateTime(2026, 3, 4));
    expect(csv, contains('2026-03-04'));
  });

  test('lists the church\'s active arms, and omits inactive ones', () {
    final csv = buildImportTemplateCsv(arms: arms);
    expect(csv, contains('# Missions'));
    expect(csv, contains('# Church Building'));
    expect(csv, isNot(contains('Retired Arm')));
  });

  test('example CATEGORY is a real arm, not a placeholder', () {
    final csv = buildImportTemplateCsv(arms: arms, exampleDate: DateTime(2026, 3, 4));
    final grid = parseCsvGrid(csv);
    final categoryIndex = templateHeaders.indexOf('CATEGORY');
    expect(grid[1][categoryIndex], 'Missions');
  });

  test('says so plainly when the church has no arms yet', () {
    final csv = buildImportTemplateCsv(arms: const []);
    expect(csv, contains('none configured yet'));
  });

  test('quotes cells that contain a comma', () {
    final csv = buildImportTemplateCsv(arms: [arm('1', 'Missions, Local')]);
    expect(csv, contains('"# Missions, Local"'));
    // And it survives a round trip.
    expect(parseCsvGrid(csv).any((r) => r.first == '# Missions, Local'), isTrue);
  });

  test('filename is derived from the church name', () {
    expect(importTemplateFileName('Demo Community Church'),
        'demo-community-church-import-template.csv');
    expect(importTemplateFileName(null), 'pillr-import-template.csv');
  });
}
