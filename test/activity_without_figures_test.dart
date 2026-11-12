import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/activity/data/activity_log_repository.dart';

void main() {
  test('no amount or total reaches the activity log, at any depth', () {
    final out = withoutFigures({
      'partnerName': 'Ama Boateng',
      'amountCedis': 500,
      'totalCedis': 2000,
      'armName': 'Tithe',
      'before': {'amountCedis': 400, 'status': 'pending'},
      'rows': [
        {'amount': 1, 'name': 'x'},
      ],
    });
    expect(out, {
      'partnerName': 'Ama Boateng',
      'armName': 'Tithe',
      'before': {'status': 'pending'},
      'rows': [
        {'name': 'x'},
      ],
    });
  });

  test('an activity line keeps no entry count either, at any depth', () {
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
