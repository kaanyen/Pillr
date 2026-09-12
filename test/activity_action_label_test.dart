import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/activity/activity_action_label.dart';

void main() {
  test('import actions read as sentences, not dotted identifiers', () {
    expect(activityActionLabel('import.commit'), 'Imported a spreadsheet');
    expect(activityActionLabel('import.undo'), 'Undid an import');
    expect(activityActionLabel('import.restore'), 'Restored an import');
    expect(activityActionLabel('entry.create'), 'Recorded a gift');
    expect(activityActionLabel('entry.approve_undo'), 'Undid an approval');
    expect(activityActionLabel('entry.void'), 'Voided an entry');
    expect(activityActionLabel('partner.merge'), 'Merged partners');
  });
}
