import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/panel_flows.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
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
import 'arm_palette.dart';

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

    String periodName(String id) =>
        periods.where((p) => p.id == id).firstOrNull?.name ?? id;
    final armTree = ref.watch(armTreeProvider);
    String armName(String id) => armTree.shownNameOf(id) ?? id;
    // A main arm's filter takes in its sub-arms' entries.
    bool inArmFilter(String armId) =>
        _armFilter == null || armTree.shownArmIdOf(armId) == _armFilter;

    return partnerAsync.when(
      loading: () => const SelPageBody(
        children: [SelCard(child: SelSkeletonRows(count: 4))],
      ),
      error: (e, _) => SelPageBody(children: [SelError(message: '$e')]),
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

        final approved = all.where((e) => e.status == 'approved').toList();
        final pending = all.where((e) => e.status == 'pending').length;
        final isRecurring = _recurring(periods, all);

        return SelPageBody(
          onRefresh: () async =>
              ref.invalidate(partnerEntriesProvider(widget.partnerId)),
          children: [
            SelPageTitle(
              title: partner.fullName,
              subtitle: [
                partner.memberId,
                partner.fellowship,
                if (isRecurring) 'Recurring partner',
              ].where((e) => e.isNotEmpty).join(' · '),
              actions: [
                if (idx?.isPastor == true || idx?.role == 'staff')
                  SelButton(
                    label: 'Edit',
                    icon: LucideIcons.pencil,
                    onPressed: () => showPartnerFormPanel(
                      context,
                      churchId: idx!.churchId,
                      uid: idx.uid,
                      existing: partner,
                    ),
                  ),
                SelButton(
                  label: 'Back',
                  kind: SelButtonKind.quiet,
                  onPressed: () => context.go('/partners'),
                ),
              ],
            ),

            SelStatRow(
              stats: [
                SelStat(
                  label: 'Total approved',
                  value: ref.watch(churchCompactMoneyProvider)(
                    partner.totalApprovedAmount,
                  ),
                  exactValue: money(partner.totalApprovedAmount),
                  footnote: '${approved.length} entries',
                ),
                SelStat(
                  label: 'Awaiting review',
                  value: '$pending',
                  footnote: pending == 0 ? 'Nothing pending' : 'In the queue',
                ),
                SelStat(
                  label: 'Status',
                  value: partner.isActive ? 'Active' : 'Inactive',
                  footnote: partner.fellowship.isEmpty
                      ? 'No fellowship'
                      : partner.fellowship,
                ),
              ],
            ),

            const SelSectionGap(factor: 0.4),

            if (partner.mergedAliases.isNotEmpty) ...[
              _MergedRecordsPanel(
                churchId: idx?.churchId ?? '',
                formerMemberIds: partner.formerMemberIds,
                records: partner.mergedAliases,
                entries: all,
                canSeparate: idx?.isPastor == true || idx?.role == 'staff',
                onChanged: () =>
                    ref.invalidate(partnerEntriesProvider(widget.partnerId)),
              ),
              const SelSectionGap(factor: 0.4),
            ],

            if (partner.allPhones.isNotEmpty ||
                partner.allEmails.isNotEmpty ||
                (partner.address ?? '').trim().isNotEmpty ||
                (partner.notes ?? '').trim().isNotEmpty ||
                (partner.mergedAliases.isEmpty &&
                    partner.formerMemberIds.isNotEmpty)) ...[
              SelPanel(
                title: 'Contact',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in partner.allPhones)
                      _Contact(LucideIcons.phone, p),
                    for (final e in partner.allEmails)
                      _Contact(LucideIcons.mail, e),
                    if ((partner.address ?? '').trim().isNotEmpty)
                      _Contact(LucideIcons.mapPin, partner.address!.trim()),
                    if ((partner.notes ?? '').trim().isNotEmpty)
                      _Contact(LucideIcons.stickyNote, partner.notes!.trim()),
                    // Old IDs from an ID change; a merge shows them above.
                    if (partner.mergedAliases.isEmpty &&
                        partner.formerMemberIds.isNotEmpty)
                      _Contact(
                        LucideIcons.history,
                        'Old member IDs: ${partner.formerMemberIds.join(", ")}',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SelSpace.x4),
            ],

            Row(
              children: [
                Expanded(child: SelSectionLabel(label: 'Giving history')),
                if (periods.isNotEmpty)
                  SizedBox(
                    width: 170,
                    child: SelSelect<String?>(
                      value: _periodFilter,
                      onChanged: (v) => setState(() {
                        _periodFilter = v;
                        _monthFilter = null;
                      }),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All periods'),
                        ),
                        for (final p in periods)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                    ),
                  ),
                const SizedBox(width: SelSpace.x2),
                if (monthOptions.isNotEmpty)
                  SizedBox(
                    width: 170,
                    child: SelSelect<MonthBucket?>(
                      value: monthFilter,
                      onChanged: (v) => setState(() => _monthFilter = v),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All months'),
                        ),
                        for (final month in monthOptions)
                          DropdownMenuItem(
                            value: month,
                            child: Text(month.label),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(width: SelSpace.x2),
                if (arms.isNotEmpty)
                  SizedBox(
                    width: 170,
                    child: SelSelect<String?>(
                      value: _armFilter,
                      onChanged: (v) => setState(() {
                        _armFilter = v;
                        _monthFilter = null;
                      }),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All arms'),
                        ),
                        for (final a in armTree.mains)
                          DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: SelSpace.x3),

            SelLedger.builder(
              minWidth: 620,
              maxVirtualHeight: 560,
              columns: const [
                SelColumn('Arm', flex: 2),
                SelColumn('Period', flex: 2),
                SelColumn.numeric('Amount', width: 130),
                SelColumn('Status', fit: SelColFit.fixed, width: 120),
                SelColumn('Date', fit: SelColFit.fixed, width: 110),
              ],
              emptyState: const SelEmpty(
                title: 'No giving recorded',
                message: 'Entries for this partner will appear here.',
              ),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final e = rows[i];
                return SelRow(
                  onTap: () => context.go('/entries/${e.id}'),
                  cells: [
                    ArmLabel(
                      armId: e.partnershipArmId,
                      name: armName(e.partnershipArmId),
                      style: SelType.bodyMedium,
                    ),
                    SelCell.secondary(periodName(e.partnershipPeriodId)),
                    EntryAmountCell(
                      entry: e,
                      formattedAmount: money(e.amountCedis),
                      tone: switch (e.status) {
                        'approved' => SelTone.positive,
                        'declined' => SelTone.negative,
                        _ => SelTone.neutral,
                      },
                    ),
                    SelStatusMark.fromString(
                      status: e.status,
                      label: e.status[0].toUpperCase() + e.status.substring(1),
                    ),
                    SelCell.secondary(
                      formatFirestoreDate(e.dateGiven, pattern: 'd MMM'),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact(this.icon, this.value);

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SelSpace.x2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Sel.ash),
          const SizedBox(width: SelSpace.x2),
          Flexible(child: Text(value, style: SelType.body)),
        ],
      ),
    );
  }
}

/// The records merged into this partner, each with the member ID it had, and
/// a way to take any one back out.
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

  /// This person's gifts. Each knows the record it came from, so every
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

  Future<void> _separate(MergedRecord r, int gifts) async {
    final ok = await selConfirm(
      context,
      title: 'Take ${r.fullName} (${r.memberId}) out?',
      message:
          '${r.fullName} becomes a separate person again with member ID '
          '${r.memberId}. Their $gifts ${gifts == 1 ? "gift goes" : "gifts go"} '
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
        '${res.moved == 1 ? "gift" : "gifts"} went back to them.',
        kind: SelNoticeKind.success,
      );
    } catch (e) {
      if (mounted) selNotice(context, '$e', kind: SelNoticeKind.error);
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
            'ID. Only its own gifts go with it.',
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
                      ? 'no gifts'
                      : '${mine.length} ${mine.length == 1 ? "gift" : "gifts"} · ${money(total)}'
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
