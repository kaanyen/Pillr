import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/seline.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../maintenance/domain/data_health.dart';

/// Before a new partner is saved: does this look like someone already on the
/// book? Stopping a duplicate here is cheaper than merging it later.
///
/// Returns true to go ahead — no likely match, or the person checked and said
/// it is someone new. Inactive partners are compared too: the duplicate is
/// often of a record someone closed.
Future<bool> confirmNotDuplicate(
  BuildContext context,
  WidgetRef ref, {
  required String churchId,
  required String fullName,
  String? phone,
  String? email,
  String fellowship = '',
}) async {
  final existing =
      await ref.read(maintenanceRepositoryProvider).allPartners(churchId);
  final matches = findDuplicatesOf(
    fullName: fullName,
    phone: phone,
    email: email,
    fellowship: fellowship,
    existing: existing,
  );
  if (matches.isEmpty || !context.mounted) return true;

  final lines = [
    for (final m in matches.take(3))
      '• ${m.b.fullName} (${[
        if (m.b.memberId.isNotEmpty) m.b.memberId,
        if (m.b.fellowship.isNotEmpty) m.b.fellowship,
        if (!m.b.isActive) 'inactive',
      ].join(', ')}) — ${m.reason}',
  ];
  return selConfirm(
    context,
    title: matches.length == 1
        ? 'This looks like someone already here'
        : 'This looks like ${matches.length} people already here',
    message:
        '${lines.join('\n')}\n\nIf it is the same person, cancel and record '
        'their giving on the existing partner. Create a new partner only if '
        'this is someone else.',
    confirmLabel: 'Create anyway',
  );
}
