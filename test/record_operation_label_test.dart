import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/operations/record_ops_repository.dart';

RecordOperation _op(String kind, Map<String, dynamic> summary, {String role = 'staff'}) => RecordOperation(
  id: 'op',
  kind: kind,
  status: 'applied',
  summary: summary,
  planned: 1,
  applied: 1,
  actorName: 'Demo Staff',
  createdAt: DateTime(2026, 11, 12),
  actorRole: role,
);

void main() {
  test('a move of one person names them', () {
    final op = _op('fellowship.move', {'from': 'Grace', 'to': 'Bethel', 'partners': ['Linda Adu'], 'activeMoved': 1});
    expect(op.label, 'Moved Linda Adu from Grace to Bethel');
  });

  test('a move of several says how many', () {
    final op = _op('fellowship.move', {'from': 'Zion', 'to': 'Grace', 'partners': ['Afia Mensah', 'Akua Frimpong'], 'activeMoved': 2});
    expect(op.label, 'Moved 2 partners from Zion to Grace');
  });

  test('rename and merge read plainly', () {
    expect(_op('fellowship.rename', {'from': 'Shilo', 'to': 'Shiloh'}).label, 'Renamed Shilo to Shiloh');
    expect(_op('fellowship.dissolve', {'from': 'Canaan', 'to': 'Hope'}).label, 'Merged Canaan into Hope');
  });
}
