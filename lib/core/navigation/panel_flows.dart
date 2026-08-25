import 'package:flutter/material.dart';

import '../../design/components/sel_side_sheet.dart';
import '../../features/partners/domain/partner.dart';
import '../../features/partners/presentation/partner_form_panel.dart';
import '../../screens/entries/entry_form_screen.dart';
import '../../screens/entries/partner_picker_panel.dart';

Future<void> showPartnerFormPanel(
  BuildContext context, {
  required String churchId,
  required String uid,
  Partner? existing,
}) {
  return showSelSideSheet<void>(
    context,
    title: existing == null ? 'Add partner' : 'Edit partner',
    subtitle: existing == null
        ? 'Member ID is assigned automatically when you save.'
        : 'Update member details for partnership records.',
    width: 480,
    child: PartnerFormPanel(
      churchId: churchId,
      uid: uid,
      existing: existing,
    ),
  );
}

Future<Partner?> showPartnerPickerPanel(
  BuildContext context, {
  required String churchId,
  required String uid,
}) {
  return showSelSideSheet<Partner>(
    context,
    title: 'Select partner',
    subtitle: 'Search by name, member ID, or fellowship.',
    width: 480,
    child: PartnerPickerPanel(churchId: churchId, uid: uid),
  );
}

Future<void> showEntryFormPanel(
  BuildContext context, {
  String? entryId,
}) {
  final isEdit = entryId != null;
  return showSelSideSheet<void>(
    context,
    title: isEdit ? 'Edit entry' : 'Record partnership',
    subtitle: isEdit
        ? 'Changes are re-recorded in the activity log.'
        : 'Who gave, how much, and toward what.',
    width: 560,
    child: EntryFormScreen(
      entryId: entryId,
      embedded: true,
    ),
  );
}
