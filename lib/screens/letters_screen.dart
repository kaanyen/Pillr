import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Partners ticked to get this month's letter now.
  final Set<String> _chosen = {};

  /// Only a partner with an email whose letters are on can be ticked.
  static bool _canChoose(_Letter l) =>
      (l.kind == _Show.sent || l.kind == _Show.failed) && l.email.isNotEmpty && l.partnerId.isNotEmpty;

  Future<void> _sendChosen(String ym, String month, List<_Letter> chosen) async {
    final again = chosen.where((l) => l.kind == _Show.sent).length;
    final ok = await selConfirm(
      context,
      title: 'Send $month\'s letter to ${chosen.length}?',
      message: again == 0
          ? 'It goes to the ${chosen.length == 1 ? 'partner' : 'partners'} you ticked, and nobody else.'
          : '$again of them already got it and will get it again. Nobody else is sent anything.',
      confirmLabel: 'Send',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(churchSettingsRepositoryProvider)
          .runMonthlyPartnerEmails(yearMonth: ym, partnerIds: [for (final l in chosen) l.partnerId]);
      if (mounted) {
        setState(_chosen.clear);
        selNotice(
          context,
          r.failed == 0
              ? 'Sent to ${r.sentNow} ${r.sentNow == 1 ? 'partner' : 'partners'}.'
              : 'Sent to ${r.sentNow}, but ${r.failed} could not be sent. They are listed as Failed.',
        );
      }
    } catch (e) {
      if (mounted) selNotice(context, '$e', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    // An admin looks after the letters' set-up and sees how each run went,
    // in counts: never who got one or how much.
    if (ref.watch(userChurchIndexProvider).valueOrNull?.isAdmin ?? false) {
      return const _AdminLetters();
    }
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
    final choosable = [for (final l in letters) if (_canChoose(l)) l];
    final notSent = [for (final l in choosable) if (l.kind == _Show.failed) l];
    final chosen = [for (final l in letters) if (_chosen.contains(l.partnerId) && _canChoose(l)) l];
    void pick(Iterable<_Letter> ls) => setState(() {
      _chosen
        ..clear()
        ..addAll(ls.map((l) => l.partnerId));
    });
    String chosenNote() {
      final names = chosen.map((l) => l.name).toList();
      final who = names.length <= 2
          ? names.join(' and ')
          : '${names.take(2).join(', ')} and ${names.length - 2} more';
      final again = [for (final l in chosen) if (l.kind == _Show.sent) l.name];
      if (again.isEmpty) return '$who.';
      if (chosen.length == 1) return '$who already got $monthName\'s and will get it again.';
      return again.length == 1
          ? '$who. ${again.single} already got $monthName\'s and will get it again.'
          : '$who. ${again.length} of them already got $monthName\'s and will get it again.';
    }

    Widget quickPick(String label, VoidCallback? onTap) => Material(
      color: Sel.card,
      shape: const StadiumBorder(side: BorderSide(color: Sel.border, width: 1.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: SelType.small.copyWith(
              color: onTap == null ? Sel.warm : Sel.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    Widget statusTag(_Letter l) => switch (l.kind) {
      _Show.sent => SelTag(l.why ?? 'Sent'),
      _Show.failed => SelTag('Failed${(l.why ?? '').isEmpty ? '' : ': ${l.why}'}', tone: SelTagTone.waiting),
      _Show.noEmail => const SelTag('No email'),
      _Show.off => const SelTag('Turned off'),
      _Show.everyone => const SizedBox.shrink(),
    };

    return SelPageBody(
      bottomBar: chosen.isEmpty
          ? null
          : SelChoiceBar(
              count: chosen.length,
              note: chosenNote(),
              busy: _busy,
              action: 'Send $monthName\'s letter to ${chosen.length}',
              onClear: () => setState(_chosen.clear),
              onAction: () => _sendChosen(current.yearMonth, monthName, chosen),
            ),
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
                    _chosen.clear();
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
              if (choosable.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Wrap(
                    spacing: SelSpace.x2,
                    runSpacing: SelSpace.x2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Choose:', style: SelType.small),
                      quickPick(
                        'Not sent yet · ${notSent.length}',
                        notSent.isEmpty ? null : () => pick(notSent),
                      ),
                      quickPick('Everyone with an email · ${choosable.length}', () => pick(choosable)),
                      if (_chosen.isNotEmpty) quickPick('Nobody', () => setState(_chosen.clear)),
                      Text(
                        "Tick anyone to send them $monthName's letter now, even if they already got it.",
                        style: SelType.small,
                      ),
                    ],
                  ),
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
                      selected: _chosen.contains(l.partnerId) && _canChoose(l),
                      leading: Semantics(
                        label: _canChoose(l) ? 'Choose ${l.name}' : '${l.name} cannot get a letter',
                        child: Checkbox(
                          value: _chosen.contains(l.partnerId) && _canChoose(l),
                          activeColor: Sel.ink,
                          onChanged: !_canChoose(l) || _busy
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _chosen.add(l.partnerId);
                                  } else {
                                    _chosen.remove(l.partnerId);
                                  }
                                }),
                        ),
                      ),
                      cells: [
                        Row(
                          children: [
                            SelFace(l.name),
                            const SizedBox(width: SelSpace.x3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: SelType.body.copyWith(color: Sel.text, fontWeight: FontWeight.w600),
                                  ),
                                  if (l.kind == _Show.noEmail)
                                    Text('No email to send to', style: SelType.small)
                                  else if (l.kind == _Show.off)
                                    Text('Letters turned off', style: SelType.small),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SelCell.secondary(l.email.isEmpty ? '—' : l.email),
                        SelCell.numeric(l.amount == 0 ? '—' : money(l.amount)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _chosen.contains(l.partnerId) && l.kind == _Show.sent
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [statusTag(l), Text('Gets it again', style: SelType.small)],
                                )
                              : statusTag(l),
                        ),
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

/// One month's run, in counts.
typedef _Summary = ({String ym, String label, int sent, int failed, int noEmail, int off, DateTime? ranAt});

final _summariesProvider = StreamProvider.autoDispose<List<_Summary>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !(idx.isAdmin || idx.isPastor)) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection('churches')
      .doc(idx.churchId)
      .collection('monthly_email_summaries')
      .orderBy('ranAt', descending: true)
      .limit(12)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              (
                ym: d.id,
                label: d.data()['monthLabel'] as String? ?? d.id,
                sent: (d.data()['sent'] as num?)?.toInt() ?? 0,
                failed: (d.data()['failed'] as num?)?.toInt() ?? 0,
                noEmail: (d.data()['noEmail'] as num?)?.toInt() ?? 0,
                off: (d.data()['turnedOff'] as num?)?.toInt() ?? 0,
                ranAt: (d.data()['ranAt'] as Timestamp?)?.toDate(),
              ),
          ]);
});

/// Monthly letters for an admin, as on the canvas (board 54).
class _AdminLetters extends ConsumerStatefulWidget {
  const _AdminLetters();

  @override
  ConsumerState<_AdminLetters> createState() => _AdminLettersState();
}

class _AdminLettersState extends ConsumerState<_AdminLetters> {
  String? _month;
  bool _busy = false;

  Future<void> _sample() async {
    setState(() => _busy = true);
    try {
      final to = await ref.read(churchSettingsRepositoryProvider).previewMonthlyPartnerEmail();
      if (mounted) selNotice(context, 'A sample with made-up names and figures is on its way to $to.');
    } catch (e) {
      if (mounted) selNotice(context, '$e', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_summariesProvider);
    final runs = list.valueOrNull ?? const <_Summary>[];
    final current = runs.where((r) => r.ym == _month).firstOrNull ?? runs.firstOrNull;

    Widget tile(String k, int v, String sub, {bool navy = false}) => Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: navy ? Sel.ink : Sel.card,
        borderRadius: BorderRadius.circular(SelRadius.card),
        border: Border.all(color: navy ? Sel.ink : Sel.border),
        boxShadow: navy ? null : SelShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: SelType.small.copyWith(color: navy ? SelNavyCard.soft : Sel.warm)),
          Text('$v', style: SelType.hero.copyWith(fontSize: 30, color: navy ? Sel.card : Sel.ink)),
          Text(sub, style: SelType.small.copyWith(color: navy ? SelNavyCard.soft : Sel.warm)),
        ],
      ),
    );

    return SelPageBody(
      children: [
        SelBreadcrumb([('Settings', () => context.go('/settings')), ('Monthly letters', null)]),
        const SizedBox(height: SelSpace.x3),
        SelPageTitle(
          title: 'Monthly letters',
          subtitle: 'The thank-you letter partners get on the 15th. You set it up; who gets one and how much stays with the pastors.',
          actions: [SelButton(label: 'Send me a sample', loading: _busy, onPressed: _busy ? null : _sample)],
        ),
        if (list.isLoading)
          const SelCard(child: SelSkeletonRows(count: 3))
        else if (current == null)
          const SelCard(
            child: SelEmpty(
              title: 'No letters yet',
              message: 'After the first run on the 15th, each month shows here as counts.',
            ),
          )
        else ...[
          Wrap(
            spacing: SelSpace.x2,
            runSpacing: SelSpace.x2,
            children: [
              for (final r in runs)
                Material(
                  color: r.ym == current.ym ? Sel.ink : Sel.card,
                  shape: StadiumBorder(side: BorderSide(color: r.ym == current.ym ? Sel.ink : Sel.border)),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => setState(() => _month = r.ym),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        r.label,
                        style: SelType.bodySm.copyWith(
                          color: r.ym == current.ym ? Sel.card : Sel.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          LayoutBuilder(
            builder: (context, c) {
              final tiles = [
                tile('Sent', current.sent, current.ranAt == null ? '' : DateFormat('d MMM, HH:mm').format(current.ranAt!)),
                tile('Could not be sent', current.failed, 'A pastor can see who and send it again', navy: current.failed > 0),
                tile('No email', current.noEmail, 'Gave, but have no email on their profile'),
                tile('Turned off', current.off, 'The church turned their letters off'),
              ];
              return Wrap(
                spacing: SelSpace.x4,
                runSpacing: SelSpace.x4,
                children: [
                  for (final t in tiles)
                    SizedBox(width: c.maxWidth >= 900 ? (c.maxWidth - SelSpace.x4 * 3) / 4 : (c.maxWidth - SelSpace.x4) / 2, child: t),
                ],
              );
            },
          ),
          const SizedBox(height: SelSpace.x4),
          Container(
            padding: const EdgeInsets.all(SelSpace.x4),
            decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(16)),
            child: Text(
              'Switch the letters on or off, choose who signs them and the address they come from in Settings, '
              'under Thanking partners. "Send me a sample" sends you the letter filled with made-up names and '
              'figures, so you can check how it looks without seeing anyone\'s giving.',
              style: SelType.bodySm.copyWith(color: Sel.ink),
            ),
          ),
        ],
      ],
    );
  }
}

