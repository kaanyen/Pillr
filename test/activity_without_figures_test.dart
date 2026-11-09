import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/activity/data/activity_log_repository.dart';

void main() {
  test('an activity line keeps no money and no entry count, at any depth', () {
    final out = withoutFigures({
      'fileName': 'october.xlsx',
      'entryCount': 14,
      'totalCedis': 19880,
      'partnersCreated': 2,
      'nested': {'amountCedis': 500, 'entryCount': 3, 'name': 'Ama'},
    });
    expect(out.keys, unorderedEquals(['fileName', 'partnersCreated', 'nested']));
    expect(out['nested'], {'name': 'Ama'});
  });
}
