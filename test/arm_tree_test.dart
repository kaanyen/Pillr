import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/arms/domain/arm_tree.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';

PartnershipArm arm(String id, int sort, {String? parent}) => PartnershipArm(
      id: id,
      churchId: 'c',
      name: id,
      isActive: true,
      sortOrder: sort,
      parentArmId: parent,
      createdBy: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  // The Airport City arrangement, before anything is grouped.
  final flat = [
    arm('rhapsody', 0),
    arm('healing', 1),
    arm('venue', 2),
    arm('service', 3),
    arm('programs', 4),
    arm('offer7', 5),
    arm('w1909', 6),
    arm('logistics', 7),
    arm('abuja', 8),
    arm('ministry', 9),
  ];

  test('ungrouped arms are all main arms, in sort order', () {
    final t = ArmTree(flat);
    expect(t.mains.map((a) => a.id), flat.map((a) => a.id));
    expect(t.familyOf('venue'), {'venue'});
  });

  test('a main arm\'s family is itself and its sub-arms', () {
    final t = ArmTree([
      arm('venue', 0),
      arm('logistics', 1, parent: 'venue'),
      arm('service', 2, parent: 'venue'),
      arm('programs', 3, parent: 'venue'),
      arm('w1909', 4),
    ]);
    expect(t.familyOf('venue'), {'venue', 'logistics', 'service', 'programs'});
    expect(t.familyOf('logistics'), {'logistics'});
    expect(t.mainOf('service')?.id, 'venue');
    expect(t.mainOf('venue'), isNull);
    expect(t.flattened.map((r) => (r.arm.id, r.isSub)).toList(), [
      ('venue', false),
      ('logistics', true),
      ('service', true),
      ('programs', true),
      ('w1909', false),
    ]);
  });

  test('a sub-arm whose main arm is missing shows as a main arm', () {
    final t = ArmTree([arm('logistics', 0, parent: 'gone')]);
    expect(t.mains.single.id, 'logistics');
    expect(t.mainOf('logistics'), isNull);
  });

  test('moves are one level deep', () {
    final t = ArmTree([
      arm('ministry', 0),
      arm('rhapsody', 1, parent: 'ministry'),
      arm('venue', 2),
    ]);
    expect(t.whyCannotMoveUnder('venue', 'ministry'), isNull);
    expect(t.whyCannotMoveUnder('venue', 'rhapsody'), isNotNull);
    expect(t.whyCannotMoveUnder('ministry', 'venue'), isNotNull);
    expect(t.whyCannotMoveUnder('venue', 'venue'), isNotNull);
  });

  test('moving writes only parent and order, and only for arms that moved', () {
    final t = ArmTree([
      arm('ministry', 0),
      arm('venue', 1),
      arm('rhapsody', 2),
    ]);
    final p = t.placementsForMove('rhapsody', 'ministry');
    expect(
      p.map((x) => (x.armId, x.parentArmId, x.sortOrder)).toList(),
      [('rhapsody', 'ministry', 1), ('venue', null, 2)],
    );
    final undo = t.undoOf(p);
    expect(
      undo.map((x) => (x.armId, x.parentArmId, x.sortOrder)).toList(),
      [('rhapsody', null, 2), ('venue', null, 1)],
    );
  });

  test('making a sub-arm a main arm puts it last', () {
    final t = ArmTree([
      arm('ministry', 0),
      arm('rhapsody', 1, parent: 'ministry'),
      arm('venue', 2),
    ]);
    final p = t.placementsForMove('rhapsody', null);
    expect(
      p.map((x) => (x.armId, x.parentArmId, x.sortOrder)).toList(),
      [('venue', null, 1), ('rhapsody', null, 2)],
    );
  });

  group('outside Configuration only main arms show', () {
    final t = ArmTree([
      arm('venue', 0),
      arm('logistics', 1, parent: 'venue'),
      arm('w1909', 2),
    ]);

    test('a sub-arm is shown as its main arm', () {
      expect(t.shownArmIdOf('logistics'), 'venue');
      expect(t.shownNameOf('logistics'), 'venue');
      expect(t.shownArmIdOf('w1909'), 'w1909');
      expect(t.shownArmIdOf('unknown'), 'unknown');
      expect(t.shownNameOf('unknown'), isNull);
    });

    test('an entry\'s own page names the exact arm', () {
      expect(t.fullNameOf('logistics'), 'venue · logistics');
      expect(t.fullNameOf('venue'), 'venue');
    });

    test('recording pickers list each main arm then its sub-arms', () {
      expect(t.recordingOptions().map((o) => o.$2).toList(),
          ['venue', 'venue · logistics', 'w1909']);
      expect(
          t.recordingOptions([t.byId('w1909')!]).map((o) => o.$2).toList(),
          ['w1909']);
    });
  });
}
