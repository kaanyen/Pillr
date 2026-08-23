import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_arm_match.dart';

PartnershipArm _arm(String id, String name, {List<String> aliases = const []}) =>
    PartnershipArm(
      aliases: aliases,
      id: id,
      churchId: 'c',
      name: name,
      description: null,
      isActive: true,
      colorHex: null,
      sortOrder: 0,
      createdBy: 'u',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

void main() {
  test('findArmMatchFromExcelCell matches extra wording after comma', () {
    final arms = [
      _arm('a1', 'Church service'),
      _arm('a2', 'Programs'),
    ];
    final m = findArmMatchFromExcelCell(
      'Church service, Programs, Rhapsody etc',
      arms,
    );
    expect(m?.id, 'a1');
  });

  test('findArmMatchFromExcelCell picks longest substring when multiple match', () {
    final arms = [
      _arm('short', 'Church'),
      _arm('long', 'Church service'),
    ];
    final m = findArmMatchFromExcelCell('Church service, notes', arms);
    expect(m?.id, 'long');
  });

  test('findArmMatchFromExcelCell segment exact match', () {
    final arms = [_arm('a', 'Programs')];
    final m = findArmMatchFromExcelCell('Venue; Programs; Other', arms);
    expect(m?.id, 'a');
  });

  test('findArmMatchFromExcelCell first word matches arm name (Rhapsody of realities)', () {
    final arms = [_arm('r1', 'Rhapsody')];
    final m = findArmMatchFromExcelCell('Rhapsody of realities', arms);
    expect(m?.id, 'r1');
  });

  test('findArmMatchFromExcelCell any word matches arm name (SUNDAY SERVICE → Service)', () {
    final arms = [_arm('s1', 'Service')];
    final m = findArmMatchFromExcelCell('SUNDAY SERVICE', arms);
    expect(m?.id, 's1');
  });

  group('remembered aliases', () {
    test('a saved alias resolves a spelling no fuzzy rule would catch', () {
      // "Super Sunday" shares nothing with "Missions" — only a decision
      // someone made previously can connect them.
      final arms = [
        _arm('a1', 'Missions', aliases: ['super sunday']),
        _arm('a2', 'Media'),
      ];
      expect(findArmMatchFromExcelCell('Super Sunday', arms)?.id, 'a1');
    });

    test('alias matching ignores case and extra whitespace', () {
      final arms = [_arm('a1', 'Missions', aliases: ['super sunday'])];
      expect(findArmMatchFromExcelCell('  SUPER   SUNDAY ', arms)?.id, 'a1');
    });

    test('an exact arm name still wins over another arm\'s alias', () {
      final arms = [
        _arm('a1', 'Missions', aliases: ['media']),
        _arm('a2', 'Media'),
      ];
      expect(findArmMatchFromExcelCell('Media', arms)?.id, 'a2');
    });

    test('aliases on an inactive arm are ignored', () {
      final arms = [
        PartnershipArm(
          id: 'a1', churchId: 'c', name: 'Retired', description: null,
          isActive: false, colorHex: null, sortOrder: 0,
          aliases: const ['super sunday'],
          createdBy: 'u', createdAt: DateTime(2024), updatedAt: DateTime(2024),
        ),
      ];
      expect(findArmMatchFromExcelCell('Super Sunday', arms), isNull);
    });
  });
}