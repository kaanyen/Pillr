import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/panel_flows.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import 'pdf_actions.dart';
import '../features/partners/domain/partner.dart';
import '../features/operations/record_ops_repository.dart';
import '../core/notifications/sel_notice.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/presentation/entry_amount_cell.dart';
import '../features/entries/monthly_records_models.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/partners/providers/partners_providers.dart';
import '../features/periods/domain/partnership_period.dart';
import '../features/periods/providers/periods_providers.dart';
import '../core/errors/plain_error.dart';

/// One partner: who they are, what they have given, and every entry.
class PartnerProfileScreen extends ConsumerStatefulWidget {
  const PartnerProfileScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  ConsumerState<PartnerProfileScreen> createState() =>
      _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends ConsumerState<PartnerProfileScreen> {
  String? _periodFilter;
  String? _armFilter;
  MonthBucket? _monthFilter;

  List<MonthBucket> _monthsIn(Iterable<PartnershipEntry> entries) {
    final months = <int, MonthBucket>{};
    for (final entry in entries) {
      final bucket = MonthBucket.fromDate(entry.dateGiven);
      months[bucket.sortKey] = bucket;
    }
    return months.values.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Given in at least three consecutive periods. Shown as a quiet tag rather
  /// than a badge — it is a fact about the record, not an award.
  bool _recurring(
    List<PartnershipPeriod> periods,
    List<PartnershipEntry> entries,
  ) {
    final approved = entries.where((e) => e.status == 'approved');
    if (approved.isEmpty) return false;
    final has = approved.map((e) => e.partnershipPeriodId).toSet();
    final ordered = [...periods]
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    var run = 0, best = 0;
    for (final p in ordered) {
      if (has.contains(p.id)) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best >= 3;
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final partnerAsync = ref.watch(partnerStreamProvider(widget.partnerId));
    final entriesAsync = ref.watch(partnerEntriesProvider(widget.partnerId));
    final periods = ref.watch(periodsStreamProvider).valueOrNull ?? [];
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];

    final armTree = ref.watch(armTreeProvider);
    String armName(String id) => armTree.shownNameOf(id) ?? id;
    // A main arm's filter takes in its sub-arms' entries.
    bool inArmFilter(String armId) =>
        _armFilter == null || armTree.shownArmIdOf(armId) == _armFilter;

    return partnerAsync.when(
      loading: () => const SelPageBody(
        children: [SelCard(child: SelSkeletonRows(count: 4))],
      ),
      error: (e, _) => SelPageBody(children: [SelError(message: plainError(e))]),
      data: (partner) {
        if (partner == null) {
          return SelPageBody(
            children: [
              SelEmpty(
                title: 'Partner not found',
                message: 'This record may have been removed.',
                actionLabel: 'Back to partners',
                onAction: () => context.go('/partners'),
              ),
            ],
          );
        }

        final all = entriesAsync.valueOrNull ?? [];
        final monthOptions = _monthsIn(
          all.where((e) {
            if (_periodFilter != null &&
                e.partnershipPeriodId != _periodFilter) {
              return false;
            }
            if (!inArmFilter(e.partnershipArmId)) return false;
            return true;
          }),
        );
        if (_monthFilter != null &&
            !monthOptions.any((m) => m == _monthFilter)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _monthFilter = null);
          });
        }
        final monthFilter =
            _monthFilter != null && monthOptions.any((m) => m == _monthFilter)
            ? _monthFilter
            : null;
        final rows = all.where((e) {
          if (_periodFilter != null && e.partnershipPeriodId != _periodFilter) {
            return false;
          }
          if (!inArmFilter(e.partnershipArmId)) return false;
          if (monthFilter != null && !monthFilter.contains(e.dateGiven)) {
            return false;
          }
          return true;
        }).toList();

        final isRecurring = _recurring(periods, all);
        final ordered = [...periods]
          ..sort((x, y) => y.startDate.compareTo(x.startDate));
        final active = periods.where((p) => p.isActive).firstOrNull ??
            ordered.firstOrNull;
        final previous = active == null
            ? null
            : ordered
                  .where((p) => p.endDate.isBefore(active.startDate))
                  .firstOrNull;
        Iterable<PartnershipEntry> inPeriod(String? id, String status) =>
            all.where((e) => e.partnershipPeriodId == id && e.status == status);
        double sum(Iterable<PartnershipEntry> es) =>
            es.fold(0, (s, e) => s + e.amountCedis);
        final appr = inPeriod(active?.id, 'approved').toList();
        final wait = inPeriod(active?.id, 'pending').toList();
        final prev = inPeriod(previous?.id, 'approved').toList();
        final pendingAll = all.where((e) => e.status == 'pending').toList();
        String span(List<PartnershipEntry> es) {
          if (es.isEmpty) return '';
          final d = es.map((e) => e.dateGiven).toList()..sort();
          final f = formatFirestoreDate(d.first, pattern: 'MMM');
          final l = formatFirestoreDate(d.last, pattern: 'MMM');
          return f == l ? ' · $f' : ' · $f to $l';
        }

        final months = <DateTime>[];
        if (active != null) {
          for (var m = DateTime(active.startDate.year, active.startDate.month);
              !m.isAfter(active.endDate) && months.length < 12;
              m = DateTime(m.year, m.month + 1)) {
            months.add(m);
          }
        }
        double inMonth(List<PartnershipEntry> es, DateTime m) => sum(
          es.where(
            (e) => e.dateGiven.year == m.year && e.dateGiven.month == m.month,
          ),
        );
        final peak = [
          for (final m in months) math.max(inMonth(appr, m), inMonth(wait, m)),
          1.0,
        ].reduce(math.max);

        Widget figure(String label, double v, String note) {
          final full = money(v);
          final dot = full.lastIndexOf('.');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: SelType.small),
              Text.rich(
                TextSpan(
                  text: dot < 0 ? full : full.substring(0, dot),
                  style: SelType.hero.copyWith(fontSize: 30, height: 1.2),
                  children: [
                    if (dot >= 0)
                      TextSpan(
                        text: full.substring(dot),
                        style: SelType.subtitle.copyWith(color: Sel.warm),
                      ),
                  ],
                ),
              ),
              Text(note, style: SelType.small),
            ],
          );
        }

        final givingCard = SelCard(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Giving in ${active?.name ?? 'this period'}',
                style: SelType.subtitle,
              ),
              const SizedBox(height: SelSpace.x4),
              Wrap(
                spacing: SelSpace.x10,
                runSpacing: SelSpace.x4,
                children: [
                  figure('Approved', sum(appr), '${appr.length} ${appr.length == 1 ? 'entry' : 'entries'}${span(appr)}'),
                  figure('Waiting for review', sum(wait), '${wait.length} ${wait.length == 1 ? 'entry' : 'entries'}'),
                  if (previous != null)
                    figure('All of ${previous.name}', sum(prev), '${prev.length} ${prev.length == 1 ? 'entry' : 'entries'}'),
                ],
              ),
              if (months.isNotEmpty) ...[
                const SizedBox(height: SelSpace.x6),
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final m in months)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final a = inMonth(appr, m);
                                    final w = inMonth(wait, m);
                                    final v = a > 0 ? a : w;
                                    final h = v == 0 ? 4.0 : 108 * v / peak;
                                    return Container(
                                      height: h.clamp(4, 108).toDouble(),
                                      decoration: BoxDecoration(
                                        color: a > 0
                                            ? Sel.sky
                                            : w > 0
                                            ? Sel.skyWash
                                            : Sel.border,
                                        borderRadius: BorderRadius.circular(10),
                                        border: a == 0 && w > 0
                                            ? Border.all(color: Sel.ink, width: 1.5)
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: SelSpace.x2),
                                Text(
                                  formatFirestoreDate(m, pattern: 'MMM')[0],
                                  style: SelType.small,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: SelSpace.x3),
                Wrap(
                  spacing: SelSpace.x4,
                  children: [
                    _Key(Sel.sky, null, 'Approved'),
                    _Key(Sel.skyWash, Sel.ink, 'Waiting for review'),
                  ],
                ),
              ],
            ],
          ),
        );

        final historyCard = SelCard(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Giving history', style: SelType.subtitle)),
                  for (final p in ordered.take(3))
                    Padding(
                      padding: const EdgeInsets.only(left: SelSpace.x2),
                      child: _Pill(
                        label: p.name,
                        on: _periodFilter == p.id,
                        onTap: () => setState(() {
                          _periodFilter = _periodFilter == p.id ? null : p.id;
                          _monthFilter = null;
                        }),
                      ),
                    ),
                  if (arms.isNotEmpty) ...[
                    const SizedBox(width: SelSpace.x2),
                    SizedBox(
                      width: 150,
                      child: SelSelect<String?>(
                        value: _armFilter,
                        onChanged: (v) => setState(() => _armFilter = v),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All arms')),
                          for (final a in armTree.mains)
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: SelSpace.x2),
              SelLedger.builder(
                bare: true,
                minWidth: 620,
                maxVirtualHeight: 560,
                columns: const [
                  SelColumn('Date given', fit: SelColFit.fixed, width: 110),
                  SelColumn('Arm', flex: 2),
                  SelColumn('Recorded by', flex: 2),
                  SelColumn('Status', flex: 2),
                  SelColumn.numeric('Amount', width: 140),
                ],
                emptyState: const SelEmpty(
                  title: 'No giving recorded',
                  message: 'Entries for this partner will appear here.',
                ),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final e = rows[i];
                  final waiting = DateTime.now().difference(e.createdAt).inDays;
                  return SelRow(
                    onTap: () => context.go('/entries/${e.id}'),
                    cells: [
                      SelCell.secondary(
                        formatFirestoreDate(e.dateGiven, pattern: 'd MMM'),
                      ),
                      SelCell.secondary(armName(e.partnershipArmId)),
                      SelCell.secondary(
                        e.importBatchId != null
                            ? 'A sheet'
                            : e.createdBySnapshot['fullName']?.toString() ?? '',
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelStatusMark.fromString(
                          status: e.status,
                          label: switch (e.status) {
                            'approved' => 'Approved',
                            'declined' => 'Sent back',
                            'voided' => 'Voided',
                            _ => 'Waiting $waiting ${waiting == 1 ? 'day' : 'days'}',
                          },
                        ),
                      ),
                      EntryAmountCell(
                        entry: e,
                        formattedAmount: money(e.amountCedis),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );

        Widget fact(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: SelSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label, style: SelType.bodySm), value],
          ),
        );
        Text val(String t, {bool mono = false}) => Text(
          t,
          style: SelType.body.copyWith(
            color: Sel.text,
            fontFamily: mono ? 'monospace' : null,
            fontWeight: mono ? FontWeight.w700 : FontWeight.w500,
          ),
        );
        final contact = SelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Contact', style: SelType.subtitle),
              const SizedBox(height: SelSpace.x2),
              fact(
                partner.allPhones.length > 1 ? 'Phones' : 'Phone',
                partner.allPhones.isEmpty
                    ? val('None yet')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [for (final p in partner.allPhones) val(p)],
                      ),
              ),
              const Divider(height: 1, color: Sel.rowLine),
              fact(
                'Email',
                val(partner.allEmails.isEmpty ? 'None yet' : partner.allEmails.join('\n')),
              ),
              const Divider(height: 1, color: Sel.rowLine),
              // Whether the monthly thank-you letter goes to this partner.
              // Pastors and staff switch it; everyone can see where it stands.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SelSpace.x3),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Monthly letter', style: SelType.bodySm),
                          val(
                            partner.allEmails.isEmpty
                                ? 'Needs an email'
                                : partner.noMonthlyLetters
                                ? 'Off'
                                : 'On',
                          ),
                        ],
                      ),
                    ),
                    if ((idx?.isPastor == true || idx?.role == 'staff') &&
                        partner.allEmails.isNotEmpty)
                      Switch(
                        value: !partner.noMonthlyLetters,
                        onChanged: (on) => ref
                            .read(partnersRepositoryProvider)
                            .setMonthlyLetters(
                              churchId: idx!.churchId,
                              partnerId: partner.id,
                              on: on,
                            ),
                      ),
                  ],
                ),
              ),
              if ((partner.address ?? '').trim().isNotEmpty) ...[
                const Divider(height: 1, color: Sel.rowLine),
                fact('Address', val(partner.address!.trim())),
              ],
              if ((partner.notes ?? '').trim().isNotEmpty) ...[
                const Divider(height: 1, color: Sel.rowLine),
                fact('Notes', val(partner.notes!.trim())),
              ],
              if (partner.formerMemberIds.isNotEmpty) ...[
                const Divider(height: 1, color: Sel.rowLine),
                fact(
                  'Old IDs',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      val(partner.formerMemberIds.join(', '), mono: true),
                      Text(
                        'Sheets with these IDs still find this partner.',
                        style: SelType.small,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );

        final waitingCard = pendingAll.isEmpty
            ? null
            : Container(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                decoration: BoxDecoration(
                  color: Sel.ink,
                  borderRadius: BorderRadius.circular(SelRadius.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pendingAll.length} ${pendingAll.length == 1 ? 'entry' : 'entries'} waiting',
                      style: SelType.subtitle.copyWith(color: Sel.card),
                    ),
                    const SizedBox(height: SelSpace.x2),
                    Text(
                      '${money(sum(pendingAll))} is waiting for a pastor to approve.',
                      style: SelType.body.copyWith(color: const Color(0xFFC9DEF3)),
                    ),
                    const SizedBox(height: SelSpace.x4),
                    Material(
                      color: Sel.card,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => context.go('/queue?filter=pending'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                          child: Text(
                            'Review in the queue',
                            style: SelType.button.copyWith(color: Sel.ink),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );

        final merges = partner.mergedAliases.isEmpty
            ? null
            : _MergedRecordsPanel(
                churchId: idx?.churchId ?? '',
                formerMemberIds: partner.formerMemberIds,
                records: partner.mergedAliases,
                entries: all,
                canSeparate: idx?.isPastor == true || idx?.role == 'staff',
                onChanged: () =>
                    ref.invalidate(partnerEntriesProvider(widget.partnerId)),
              );

        final words = partner.fullName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
        final header = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Sel.skyWash, shape: BoxShape.circle),
              child: Text(
                words.take(2).map((w) => w[0].toUpperCase()).join(),
                style: SelType.subtitle.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: SelSpace.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(partner.fullName, style: SelType.title),
                  Wrap(
                    spacing: SelSpace.x2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        partner.memberId,
                        style: SelType.bodySm.copyWith(fontFamily: 'monospace'),
                      ),
                      if (partner.fellowship.isNotEmpty) ...[
                        Text('·', style: SelType.bodySm),
                        SelLink(
                          label: partner.fellowship,
                          onTap: () => context.go(
                            '/fellowships/${Uri.encodeComponent(partner.fellowship.toLowerCase())}',
                          ),
                        ),
                      ],
                      Text(
                        '· Partner since ${formatFirestoreDate(partner.createdAt, pattern: 'MMM y')}',
                        style: SelType.bodySm,
                      ),
                      SelStatusTag(
                        status: partner.isActive ? SelStatus.active : SelStatus.inactive,
                        label: partner.isActive
                            ? (isRecurring ? 'Active · recurring' : 'Active')
                            : 'Closed',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // A statement covers everything the partner gave, so only a
            // pastor, who sees all of it, can make one.
            if (idx?.isPastor == true) ...[
              SelButton(
                label: 'Statement',
                onPressed: () => sharePartnerStatement(
                  context,
                  ref,
                  partner: partner,
                  entries: all,
                ),
              ),
              const SizedBox(width: SelSpace.x2),
            ],
            if (idx?.isPastor == true || idx?.role == 'staff') ...[
              SelButton(
                label: 'Edit',
                onPressed: () => showPartnerFormPanel(
                  context,
                  churchId: idx!.churchId,
                  uid: idx.uid,
                  existing: partner,
                ),
              ),
              const SizedBox(width: SelSpace.x2),
              SelButton.cyan(
                label: 'Record giving',
                onPressed: () => showEntryFormPanel(context),
              ),
            ],
          ],
        );

        final side = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            contact,
            if (waitingCard != null) ...[const SizedBox(height: SelSpace.x4), waitingCard],
            if (merges != null) ...[const SizedBox(height: SelSpace.x4), merges],
          ],
        );
        final mainCol = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [givingCard, const SizedBox(height: SelSpace.x4), historyCard],
        );

        return SelPageBody(
          onRefresh: () async =>
              ref.invalidate(partnerEntriesProvider(widget.partnerId)),
          children: [
            SelBreadcrumb([
              ('Partners', () => context.go('/partners')),
              (partner.fullName, null),
            ]),
            const SizedBox(height: SelSpace.x4),
            header,
            const SizedBox(height: SelSpace.x6),
            LayoutBuilder(
              builder: (context, c) => c.maxWidth < 980
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [mainCol, const SizedBox(height: SelSpace.x4), side],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: mainCol),
                        const SizedBox(width: SelSpace.x4),
                        SizedBox(width: 320, child: side),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: on ? Sel.ink : Sel.card,
    shape: StadiumBorder(side: BorderSide(color: on ? Sel.ink : Sel.border)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          label,
          style: SelType.bodySm.copyWith(
            color: on ? Sel.card : Sel.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key(this.fill, this.edge, this.label);

  final Color fill;
  final Color? edge;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(3),
          border: edge == null ? null : Border.all(color: edge!),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: SelType.small),
    ],
  );
}

class _MergedRecordsPanel extends ConsumerStatefulWidget {
  const _MergedRecordsPanel({
    required this.churchId,
    required this.formerMemberIds,
    required this.records,
    required this.entries,
    required this.canSeparate,
    required this.onChanged,
  });

  final String churchId;
  final List<String> formerMemberIds;
  final List<MergedRecord> records;

  /// This person's giving. Each knows the record it came from, so every
  /// record below can show its own.
  final List<PartnershipEntry> entries;
  final bool canSeparate;
  final VoidCallback onChanged;

  @override
  ConsumerState<_MergedRecordsPanel> createState() =>
      _MergedRecordsPanelState();
}

class _MergedRecordsPanelState extends ConsumerState<_MergedRecordsPanel> {
  String? _busy;

  Future<void> _separate(MergedRecord r, int entries) async {
    final ok = await selConfirm(
      context,
      title: 'Take ${r.fullName} (${r.memberId}) out?',
      message:
          '${r.fullName} becomes a separate person again with member ID '
          '${r.memberId}. Their $entries ${entries == 1 ? "entry goes" : "entries go"} '
          'back to them, with their own phone and email. Everyone else stays '
          'merged. You can undo this.',
      confirmLabel: 'Take them out',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = r.memberId);
    try {
      final res = await ref
          .read(recordOpsRepositoryProvider)
          .partnerUnmerge(churchId: widget.churchId, memberId: r.memberId);
      ref.invalidate(partnersStreamProvider(false));
      invalidateEntryDerivedData(ref);
      widget.onChanged();
      if (!mounted) return;
      selNotice(
        context,
        '${r.fullName} (${r.memberId}) is a separate person again. ${res.moved} '
        '${res.moved == 1 ? "entry" : "entries"} went back to them.',
        kind: SelNoticeKind.success,
      );
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final withRecord = {for (final r in widget.records) r.memberId};
    final otherIds = [
      for (final id in widget.formerMemberIds)
        if (!withRecord.contains(id)) id,
    ];
    String ending(String phone) {
      final d = phone.replaceAll(RegExp(r'\D'), '');
      return d.length <= 4 ? phone : 'ends ${d.substring(d.length - 4)}';
    }

    return SelPanel(
      title: 'Records merged into this person',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This person was made from ${widget.records.length} records. If one '
            'of them is really someone else, take that record out by its member '
            'ID. Only its own giving goes with it.',
            style: SelType.bodyMuted,
          ),
          const SizedBox(height: SelSpace.x3),
          for (final r in widget.records) ...[
            Builder(
              builder: (context) {
                final mine = [
                  for (final e in widget.entries)
                    if (e.mergedFromPartnerId == r.partnerId) e,
                ]..sort((a, b) => a.dateGiven.compareTo(b.dateGiven));
                final total = mine
                    .where((e) => e.countsTowardTotals)
                    .fold<double>(0, (n, e) => n + e.amountCedis);
                final details = [
                  r.memberId.isEmpty ? 'no member ID' : r.memberId,
                  if (r.fellowship.isNotEmpty) r.fellowship,
                  for (final p in r.phones) ending(p),
                  if (r.emails.isNotEmpty) r.emails.join(', '),
                  mine.isEmpty
                      ? 'no giving'
                      : '${mine.length} ${mine.length == 1 ? "entry" : "entries"} · ${money(total)}'
                            ' · ${formatFirestoreDate(mine.first.dateGiven, pattern: 'd MMM y')}'
                            '${mine.length > 1 ? " to ${formatFirestoreDate(mine.last.dateGiven, pattern: 'd MMM y')}" : ""}',
                ];
                return Container(
                  padding: const EdgeInsets.all(SelSpace.x3),
                  decoration: BoxDecoration(
                    color: Sel.canvas,
                    borderRadius: BorderRadius.circular(SelRadius.card),
                    border: Border.all(color: Sel.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.self
                                  ? '${r.fullName} · the record that was kept'
                                  : r.fullName,
                              style: SelType.bodyMedium,
                            ),
                            Text(details.join('  ·  '), style: SelType.small),
                          ],
                        ),
                      ),
                      if (widget.canSeparate && r.memberId.isNotEmpty)
                        SelButton(
                          label: _busy == r.memberId ? 'Working…' : 'Take out',
                          kind: SelButtonKind.quiet,
                          dense: true,
                          onPressed: _busy != null
                              ? null
                              : () => _separate(r, mine.length),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: SelSpace.x2),
          ],
          if (otherIds.isNotEmpty)
            Text(
              'Also known as ${otherIds.join(", ")}. '
              'Sheets with these IDs still find this person.',
              style: SelType.small,
            ),
        ],
      ),
    );
  }
}
