import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/domain/monthly_email_report.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/partners/providers/partners_providers.dart';

final _reportsProvider = StreamProvider.autoDispose<List<MonthlyEmailReport>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isPastor) return Stream.value(const []);
  return ref.watch(churchSettingsRepositoryProvider).watchMonthlyEmailReports(idx.churchId);
});

final _deliveriesProvider =
    StreamProvider.autoDispose.family<List<MonthlyEmailDelivery>, String>((ref, ym) {
      final idx = ref.watch(userChurchIndexProvider).valueOrNull;
      if (idx == null || !idx.isPastor) return Stream.value(const []);
      return ref
          .watch(churchSettingsRepositoryProvider)
          .watchMonthlyEmailDeliveries(idx.churchId, ym);
    });

enum _Show { everyone, sent, failed, noEmail, off }

/// One partner's line for a month: who, where it went, what they gave, and
/// what happened to the letter.
typedef _Letter = ({
  String partnerId,
  String name,
  String email,
  double amount,
  _Show kind,
  String? why,
  DateTime? at,
});

/// Settings · Monthly letters, as on the canvas (board 50): one month at a
/// time, who the thank-you letter reached, who it could not, and why. Pastors
/// only, like the letters themselves.
class LettersScreen extends ConsumerStatefulWidget {
  const LettersScreen({super.key});

  @override
  ConsumerState<LettersScreen> createState() => _LettersScreenState();
}

class _LettersScreenState extends ConsumerState<LettersScreen> {
  String? _month;
  _Show _show = _Show.everyone;
  bool _busy = false;

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final to = await ref.read(churchSettingsRepositoryProvider).previewMonthlyPartnerEmail();
      if (mounted) selNotice(context, 'A preview is on its way to $to.');
    } catch (e) {
      if (mounted) selNotice(context, '$e', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendRest(String ym, String label) async {
    final ok = await selConfirm(
      context,
      title: 'Send $label letters not sent yet?',
      message:
          'Partners who already got $label\'s letter are skipped, so nobody gets it twice.',
      confirmLabel: 'Send',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(churchSettingsRepositoryProvider).runMonthlyPartnerEmails(yearMonth: ym);
      if (mounted) {
        selNotice(
          context,
          r.failed == 0
              ? 'Done. ${r.sent} letters have gone out for $label.'
              : 'Done, but ${r.failed} could not be sent. They are listed as Failed.',
        );
      }
    } catch (e) {
      if (mounted) selNotice(context, '$e', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final reports = ref.watch(_reportsProvider);
    final settings = ref.watch(churchSettingsProvider).valueOrNull;
    final partners = ref.watch(partnersStreamProvider(false)).valueOrNull ?? const [];
    final byId = {for (final p in partners) p.id: p};
    final list = reports.valueOrNull ?? const <MonthlyEmailReport>[];
    final current = list.where((r) => r.yearMonth == _month).firstOrNull ??
        list.firstOrNull;

    final title = SelPageTitle(
      title: 'Monthly letters',
      subtitle: settings?.sendMonthlyPartnerEmails == true
          ? 'The thank-you letter partners get on the 15th, and who it reached'
          : 'Letters are off. Turn them on in Settings and partners get one on the 15th.',
      actions: [
        SelButton(label: 'Send me a preview', onPressed: _busy ? null : _preview),
        if (current != null) ...[
          const SizedBox(width: SelSpace.x2),
          SelButton.cyan(
            label: 'Send the ones not sent',
            loading: _busy,
            onPressed: _busy ? null : () => _sendRest(current.yearMonth, current.monthLabel),
          ),
        ],
      ],
    );

    if (reports.isLoading) {
      return const SelPageBody(children: [SelCard(child: SelSkeletonRows(count: 5))]);
    }

    final breadcrumb = SelBreadcrumb([
      ('Settings', () => context.go('/settings')),
      ('Monthly letters', null),
    ]);

    if (current == null) {
      return SelPageBody(
        children: [
          breadcrumb,
          const SizedBox(height: SelSpace.x3),
          title,
          const SelCard(
            child: SelEmpty(
              title: 'No letters yet',
              message: 'After the first run on the 15th, each month shows here with who the letter reached.',
            ),
          ),
        ],
      );
    }

    final deliveries = ref.watch(_deliveriesProvider(current.yearMonth)).valueOrNull ?? const [];
    final failedIds = {for (final f in current.failed) f.partnerId};
    final letters = <_Letter>[
      for (final d in deliveries)
        if (!failedIds.contains(d.partnerId))
          (
            partnerId: d.partnerId,
            name: byId[d.partnerId]?.fullName ?? 'A partner',
            email: d.email,
            amount: d.amount,
            kind: _Show.sent,
            why: d.status == 'dry_run' ? 'Practice run' : null,
            at: d.sentAt,
          ),
      for (final f in current.failed)
        (
          partnerId: f.partnerId,
          name: f.fullName,
          email: f.email,
          amount: 0,
          kind: _Show.failed,
          why: f.error,
          at: current.ranAt,
        ),
      for (final s in current.skippedNoEmail)
        (partnerId: s.partnerId, name: s.fullName, email: '', amount: s.amount, kind: _Show.noEmail, why: null, at: null),
      for (final s in current.skippedOptedOut)
        (partnerId: s.partnerId, name: s.fullName, email: '', amount: s.amount, kind: _Show.off, why: null, at: null),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    int count(_Show k) => k == _Show.everyone ? letters.length : letters.where((l) => l.kind == k).length;
    final shown = [for (final l in letters) if (_show == _Show.everyone || l.kind == _show) l];
    final monthName = current.monthLabel.split(' ').first;

    Widget statusTag(_Letter l) => switch (l.kind) {
      _Show.sent => SelTag(l.why ?? 'Sent'),
      _Show.failed => SelTag('Failed${(l.why ?? '').isEmpty ? '' : ': ${l.why}'}', tone: SelTagTone.waiting),
      _Show.noEmail => const SelTag('No email'),
      _Show.off => const SelTag('Turned off'),
      _Show.everyone => const SizedBox.shrink(),
    };

    return SelPageBody(
      children: [
        breadcrumb,
        const SizedBox(height: SelSpace.x3),
        title,
        Wrap(
          spacing: SelSpace.x2,
          runSpacing: SelSpace.x2,
          children: [
            for (final r in list)
              Material(
                color: r.yearMonth == current.yearMonth ? Sel.ink : Sel.card,
                shape: StadiumBorder(
                  side: BorderSide(color: r.yearMonth == current.yearMonth ? Sel.ink : Sel.border),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => setState(() {
                    _month = r.yearMonth;
                    _show = _Show.everyone;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      r.monthLabel,
                      style: SelType.bodySm.copyWith(
                        color: r.yearMonth == current.yearMonth ? Sel.card : Sel.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: SelSpace.x4),
        if (current.skipReason != null) ...[
          Container(
            padding: const EdgeInsets.all(SelSpace.x4),
            decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(16)),
            child: Text(
              'This month did not run: ${current.skipReason}.',
              style: SelType.bodySm.copyWith(color: Sel.ink),
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        SelCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelCountTabs<_Show>(
                selected: _show,
                onSelect: (s) => setState(() => _show = s),
                tabs: [
                  (_Show.everyone, 'Everyone', count(_Show.everyone)),
                  (_Show.sent, 'Sent', count(_Show.sent)),
                  (_Show.failed, 'Failed', count(_Show.failed)),
                  (_Show.noEmail, 'No email', count(_Show.noEmail)),
                  (_Show.off, 'Turned off', count(_Show.off)),
                ],
              ),
              SelLedger(
                bare: true,
                minWidth: 760,
                columns: [
                  const SelColumn('Partner', flex: 3),
                  const SelColumn('Email', flex: 3),
                  SelColumn.numeric('$monthName giving', width: 140),
                  const SelColumn('Letter', flex: 3),
                  const SelColumn('Sent', fit: SelColFit.fixed, width: 120),
                ],
                emptyState: const SelEmpty(title: 'Nobody here', message: 'No letters in this group.'),
                rows: [
                  for (final l in shown)
                    SelRow(
                      onTap: l.partnerId.isEmpty ? null : () => context.go('/partners/${l.partnerId}'),
                      cells: [
                        Row(
                          children: [
                            SelFace(l.name),
                            const SizedBox(width: SelSpace.x3),
                            Expanded(
                              child: Text(
                                l.name,
                                overflow: TextOverflow.ellipsis,
                                style: SelType.body.copyWith(color: Sel.text, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        SelCell.secondary(l.email.isEmpty ? '—' : l.email),
                        SelCell.numeric(l.amount == 0 ? '—' : money(l.amount)),
                        Align(alignment: Alignment.centerLeft, child: statusTag(l)),
                        SelCell.secondary(l.at == null ? '—' : DateFormat('d MMM, HH:mm').format(l.at!)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        if (count(_Show.noEmail) > 0) ...[
          const SizedBox(height: SelSpace.x4),
          SelCard(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: SelSpace.x3,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${count(_Show.noEmail)} ${count(_Show.noEmail) == 1 ? 'partner' : 'partners'} gave in $monthName but ${count(_Show.noEmail) == 1 ? 'has' : 'have'} no email',
                      style: SelType.subtitle,
                    ),
                    const SizedBox(height: SelSpace.x1),
                    Text(
                      "Add an email on their profile and they get next month's letter.",
                      style: SelType.bodySm,
                    ),
                  ],
                ),
                SelButton(
                  label: 'See them',
                  onPressed: () => setState(() => _show = _Show.noEmail),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
