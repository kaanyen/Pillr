import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/activity/activity_action_label.dart';

void main() {
  test('import actions read as sentences, not dotted identifiers', () {
    expect(activityActionLabel('import.commit'), 'Imported a spreadsheet');
    expect(activityActionLabel('import.undo'), 'Undid an import');
    expect(activityActionLabel('import.restore'), 'Restored an import');
    expect(activityActionLabel('entry.create'), 'Recorded an entry');
    expect(activityActionLabel('entry.approve_undo'), 'Undid an approval');
    expect(activityActionLabel('entry.void'), 'Voided an entry');
    expect(activityActionLabel('partner.merge'), 'Merged partners');
    expect(activityActionLabel('partner.tidy'), 'Tidied partner names');
    expect(activityActionLabel('totals.repair'), 'Corrected ledger totals');
    expect(
      activityActionLabel('settings.exchange_rates'),
      'Updated exchange rates',
    );
    expect(activityActionLabel('fellowship.create'), 'Created a fellowship');
    expect(activityActionLabel('fellowship.merge'), 'Merged fellowships');
    expect(
      activityActionLabel('fellowship.move'),
      'Moved partners between fellowships',
    );
  });
}
