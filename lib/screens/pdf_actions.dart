import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
import '../core/utils/giving_ledger_report_models.dart';
import '../core/utils/partner_statement_pdf.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/partners/domain/partner.dart';
import '../features/periods/providers/periods_providers.dart';
import '../features/users/providers/users_providers.dart';
import '../core/errors/plain_error.dart';

/// The name a statement or receipt is signed with: the church's primary
/// pastor, the pastor making it, or nobody (staff cannot read the list of
/// people, and an unsigned page beats a wrong name).
String _signedBy(WidgetRef ref) {
  final settings = ref.read(churchSettingsProvider).valueOrNull;
  final idx = ref.read(userChurchIndexProvider).valueOrNull;
  final me = ref.read(churchUserProfileProvider).valueOrNull;
  final users = ref.read(churchUsersProvider).valueOrNull ?? const [];
  final primary = users.where((u) => u.uid == settings?.primaryPastorUid).firstOrNull;
  if (primary != null) return primary.fullName;
  if (idx?.isPastor == true && me != null) return me.fullName;
  return '';
}

String _file(String what, String name, DateTime on) {
  final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  final d = '${on.year}-${on.month.toString().padLeft(2, '0')}-${on.day.toString().padLeft(2, '0')}';
  return 'pillr-$what-$slug-$d.pdf';
}

/// A partner's giving statement for the active period, from their approved
/// entries.
Future<void> sharePartnerStatement(
  BuildContext context,
  WidgetRef ref, {
  required Partner partner,
  required List<PartnershipEntry> entries,
}) async {
  final settings = ref.read(churchSettingsProvider).valueOrNull;
  final period = ref.read(activePeriodProvider);
  final tree = ref.read(armTreeProvider);
  final me = ref.read(churchUserProfileProvider).valueOrNull;
  if (period == null) {
    selNotice(context, 'Open a giving period first: a statement covers one.', kind: SelNoticeKind.error);
    return;
  }
  final now = DateTime.now();
  final lines = [
    for (final e in entries)
      if (e.status == 'approved' && e.partnershipPeriodId == period.id)
        StatementLine(
          date: e.dateGiven,
          arm: tree.shownNameOf(e.partnershipArmId) ?? e.armSnapshot['name']?.toString() ?? '',
          amount: e.amountCedis,
        ),
  ];
  try {
    await sharePartnerStatementPdf(
      PartnerStatementData(
        churchName: ref.read(churchNameProvider) ?? 'Church',
        partnerName: partner.fullName,
        memberId: partner.memberId,
        fellowship: partner.fellowship,
        periodName: period.name,
        periodStart: period.startDate,
        periodEnd: period.endDate,
        lines: lines,
        pastorName: _signedBy(ref),
        madeBy: me?.fullName ?? '',
        madeAt: now,
        checkCode: GivingLedgerReportBuilder.verificationId(now),
        currencySymbol: (settings?.currency ?? 'GHS').toUpperCase(),
        markColorHex: settings?.primaryColorHex,
      ),
      logoUrl: settings?.logoUrl,
      filename: _file('statement', partner.fullName, now),
    );
  } catch (e) {
    if (context.mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
  }
}

/// A receipt for one approved entry.
Future<void> shareEntryReceipt(
  BuildContext context,
  WidgetRef ref, {
  required PartnershipEntry entry,
}) async {
  final settings = ref.read(churchSettingsProvider).valueOrNull;
  final tree = ref.read(armTreeProvider);
  final periods = ref.read(periodsStreamProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  final partner = entry.partnerSnapshot;
  try {
    await shareEntryReceiptPdf(
      EntryReceiptData(
        churchName: ref.read(churchNameProvider) ?? 'Church',
        partnerName: partner['fullName']?.toString() ?? '',
        memberId: partner['memberId']?.toString() ?? '',
        fellowship: partner['fellowship']?.toString() ?? '',
        amount: entry.amountCedis,
        arm: tree.fullNameOf(entry.partnershipArmId) ?? entry.armSnapshot['name']?.toString() ?? '',
        dateGiven: entry.dateGiven,
        periodName: periods.where((p) => p.id == entry.partnershipPeriodId).firstOrNull?.name ?? '',
        approvedAt: entry.reviewedAt,
        approvedBy: entry.reviewedBySnapshot?['fullName']?.toString() ?? 'A pastor',
        recordedBy: entry.importBatchId != null
            ? 'A sheet brought in by ${entry.createdBySnapshot['fullName'] ?? 'the church'}'
            : entry.createdBySnapshot['fullName']?.toString() ?? '',
        receiptNumber: receiptNumberFor(entry.id),
        pastorName: _signedBy(ref),
        madeAt: now,
        note: entry.notes,
        currencySymbol: (settings?.currency ?? 'GHS').toUpperCase(),
        markColorHex: settings?.primaryColorHex,
      ),
      logoUrl: settings?.logoUrl,
      filename: _file('receipt', partner['fullName']?.toString() ?? 'entry', now),
    );
  } catch (e) {
    if (context.mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
  }
}
