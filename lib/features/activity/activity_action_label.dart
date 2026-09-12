/// Plain-language labels for activity log actions.
///
/// The log stores machine names (`import.commit`). The ledger should read as
/// something a pastor can scan, not a dotted identifier.
String activityActionLabel(String action) => switch (action) {
      'import.commit' => 'Imported a spreadsheet',
      'import.undo' => 'Undid an import',
      'import.void' => 'Cleared an import',
      'import.restore' => 'Restored an import',
      'import.reassign' => 'Moved an import',
      'import.reassign_undo' => 'Moved an import back',
      'import.rename' => 'Named an import',
      'import.rename_undo' => 'Reverted an import name',
      'import.batch_edit' => 'Corrected an import',
      'import.batch_edit_undo' => 'Reverted import corrections',
      'entry.create' => 'Recorded a gift',
      'entry.update' => 'Updated an entry',
      'entry.approve' => 'Approved an entry',
      'entry.approve_undo' => 'Undid an approval',
      'entry.decline' => 'Sent an entry back',
      'entry.decline_undo' => 'Undid a send-back',
      'entry.void' => 'Voided an entry',
      'entry.restore' => 'Restored an entry',
      'entry.delete' => 'Deleted an entry',
      'partner.create' => 'Added a partner',
      'partner.update' => 'Updated a partner',
      'partner.merge' => 'Merged partners',
      _ => action.replaceAll('.', ' ').replaceAll('_', ' '),
    };
