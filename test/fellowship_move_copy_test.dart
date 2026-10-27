import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/screens/fellowship_manage_view.dart';

void main() {
  test('one partner names who leaves and who they join', () {
    expect(
      fellowshipMoveConfirmBody(
        names: const ['Ama Mensah'],
        from: 'Bethel',
        into: 'Zion',
      ),
      'Ama Mensah leaves Bethel and joins Zion.',
    );
  });

  test('several from one fellowship keep the group names', () {
    expect(fellowshipMoveFromLabel(const ['Bethel', 'Bethel']), 'Bethel');
    expect(
      fellowshipMoveConfirmBody(
        names: const ['Ama Mensah', 'Kofi Boateng', 'Yaw'],
        from: 'Bethel',
        into: 'Zion',
      ),
      '3 partners leave Bethel and join Zion.',
    );
  });

  test('mixed origins drop the leave clause', () {
    expect(
      fellowshipMoveFromLabel(const ['Bethel', 'Grace', '']),
      'Bethel · Grace · no fellowship',
    );
    expect(
      fellowshipMoveConfirmBody(
        names: const ['Ama Mensah', 'Kofi Boateng'],
        from: 'Bethel · Grace',
        into: 'Zion',
      ),
      '2 partners join Zion.',
    );
  });
}
