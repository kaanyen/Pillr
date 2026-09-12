import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
import '../features/activity/activity_log_helper.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/maintenance/data/maintenance_repository.dart';
import '../features/maintenance/domain/data_health.dart';
import '../features/maintenance/domain/totals_audit.dart';
import '../features/partners/providers/partners_providers.dart';

/// Tools — the repairs a giving ledger needs after a few years of use.
///
/// Every one of these follows the same shape, and it matters: **scan, show,
/// then ask**. None of them changes anything on arrival. A church's giving
/// records are about real people and real money, so a tool that tidied on
/// sight would be worse than no tool — the point is to make a problem
/// visible and let someone decide.
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  String? _running;

  TotalsAuditReport? _totals;
  List<DuplicatePartnerPair>? _dupPartners;
  List<DuplicateEntryPair>? _dupEntries;
  List<PartnerDataIssue>? _partnerIssues;
  int _scanned = 0;

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final canManage = (idx?.isPastor ?? false) || (idx?.isAdmin ?? false);

    if (!canManage) {
      return const SelPageBody(
        maxWidth: 640,
        children: [
          SelEmpty(
            title: 'Not your tools',
            message: 'Repairs to the ledger are done by a pastor or an admin.',
          ),
        ],
      );
    }

    return SelPageBody(
      children: [
        const SelPageTitle(
          title: 'Tools',
          subtitle:
              'Checks and repairs for the ledger. Nothing changes until you say so.',
        ),

        _ToolCard(
          icon: LucideIcons.scale,
          title: 'Check the totals',
          blurb:
              'Every partner and period total is kept up to date by a background '
              'job. If one ever fails, nothing tells you — the figure just stays '
              'wrong. This adds the entries up again and compares.',
          runLabel: 'Check totals',
          running: _running == 'totals',
          progress: _running == 'totals' && _scanned > 0
              ? '$_scanned entries read'
              : null,
          onRun: () => _run('totals', () async {
            final report = await ref
                .read(maintenanceRepositoryProvider)
                .auditTotals(
                  idx!.churchId,
                  onProgress: (n) {
                    if (mounted) setState(() => _scanned = n);
                  },
                );
            if (mounted) setState(() => _totals = report);
          }),
          result: _totals == null
              ? null
              : _TotalsResult(
                  report: _totals!,
                  money: money,
                  onRepair: () => _run('repair', () async {
                    final all = [
                      ..._totals!.partnerDrift,
                      ..._totals!.periodDrift,
                    ];
                    final n = await ref
                        .read(maintenanceRepositoryProvider)
                        .repairTotals(churchId: idx!.churchId, drift: all);
                    if (!context.mounted) return;
                    setState(() => _totals = null);
                    ref.invalidate(partnersStreamProvider(false));
                    invalidateEntryDerivedData(ref);
                    selNotice(context, 'Corrected $n ${n == 1 ? "total" : "totals"}.');
                  }),
                  repairing: _running == 'repair',
                ),
        ),

        const SizedBox(height: SelSpace.x4),

        _ToolCard(
          icon: LucideIcons.users,
          title: 'Merge duplicate partners',
          blurb:
              'The same person entered twice — usually once by hand and once by '
              'an import. Matches on member ID, phone number, then name.',
          runLabel: 'Find duplicates',
          running: _running == 'dupPartners',
          onRun: () => _run('dupPartners', () async {
            final pairs = await ref
                .read(maintenanceRepositoryProvider)
                .scanDuplicatePartners(idx!.churchId);
            if (mounted) setState(() => _dupPartners = pairs);
          }),
          result: _dupPartners == null
              ? null
              : _DuplicatePartnersResult(
                  pairs: _dupPartners!,
                  money: money,
                  onMerge: (pair, keepA) => _merge(pair, keepA, idx!.churchId),
                  busy: _running == 'merge',
                ),
        ),

        const SizedBox(height: SelSpace.x4),

        _ToolCard(
          icon: LucideIcons.copy,
          title: 'Find duplicate gifts',
          blurb:
              'The same gift recorded twice — same partner, arm, period, date '
              'and amount. The importer catches these on the way in; nothing '
              'catches the ones typed by hand.',
          runLabel: 'Find duplicates',
          running: _running == 'dupEntries',
          progress: _running == 'dupEntries' && _scanned > 0
              ? '$_scanned entries read'
              : null,
          onRun: () => _run('dupEntries', () async {
            final pairs = await ref
                .read(maintenanceRepositoryProvider)
                .scanDuplicateEntries(
                  idx!.churchId,
                  onProgress: (n) {
                    if (mounted) setState(() => _scanned = n);
                  },
                );
            if (mounted) setState(() => _dupEntries = pairs);
          }),
          result: _dupEntries == null
              ? null
              : _DuplicateEntriesResult(
                  pairs: _dupEntries!,
                  money: money,
                  onVoid: (pair) => _voidDuplicate(pair, idx!.churchId),
                  busy: _running == 'voidDup',
                ),
        ),

        const SizedBox(height: SelSpace.x4),

        _ToolCard(
          icon: LucideIcons.userCheck,
          title: 'Tidy the partner list',
          blurb:
              'Names and fellowships that are not in the house style, partners '
              'with no member ID or fellowship, and member IDs used twice.',
          runLabel: 'Check partners',
          running: _running == 'partnerData',
          onRun: () => _run('partnerData', () async {
            final issues = await ref
                .read(maintenanceRepositoryProvider)
                .scanPartnerData(idx!.churchId);
            if (mounted) setState(() => _partnerIssues = issues);
          }),
          result: _partnerIssues == null
              ? null
              : _PartnerDataResult(
                  issues: _partnerIssues!,
                  busy: _running == 'fixCasing',
                  onFixCasing: () => _run('fixCasing', () async {
                    final n = await ref
                        .read(maintenanceRepositoryProvider)
                        .fixPartnerCasing(
                          churchId: idx!.churchId,
                          issues: _partnerIssues!,
                        );
                    if (!context.mounted) return;
                    setState(() => _partnerIssues = null);
                    ref.invalidate(partnersStreamProvider(false));
                    selNotice(context, 'Corrected $n ${n == 1 ? "name" : "names"}.');
                  }),
                ),
        ),
      ],
    );
  }

  Future<void> _run(String key, Future<void> Function() body) async {
    if (_running != null) return;
    setState(() {
      _running = key;
      _scanned = 0;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) selNotice(context, '$e', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _merge(
    DuplicatePartnerPair pair,
    bool keepA,
    String churchId,
  ) async {
    final keep = keepA ? pair.a : pair.b;
    final absorb = keepA ? pair.b : pair.a;
    final actor = ref.read(churchUserProfileProvider).valueOrNull;
    if (actor == null) return;

    await _run('merge', () async {
      final repo = ref.read(maintenanceRepositoryProvider);
      final entries = await repo.entriesForPartners(churchId, [keep.id, absorb.id]);
      final plan = planPartnerMerge(keep: keep, absorb: absorb, allEntries: entries);

      if (!mounted) return;
      final ok = await selConfirm(
        context,
        title: 'Merge into ${keep.fullName}?',
        message:
            '${plan.entriesToMove.length} entries move from ${absorb.fullName} '
            'to ${keep.fullName}, whose total becomes '
            '${ref.read(churchMoneyFormatProvider)(plan.resultingTotal)} across '
            '${plan.resultingCount} entries. ${absorb.fullName} is closed, not '
            'deleted.',
        confirmLabel: 'Merge',
      );
      if (!ok) return;

      final moved = await repo.mergePartners(
        churchId: churchId,
        plan: plan,
        actor: actor,
      );
      if (!mounted) return;
      setState(() => _dupPartners = null);
      ref.invalidate(partnersStreamProvider(false));
      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: 'partner.merge',
        entityType: 'partner',
        entityId: keep.id,
        entitySnapshot: {
          'keptName': keep.fullName,
          'absorbedName': absorb.fullName,
          'moved': moved,
        },
      );
      if (!context.mounted) return;
      selNotice(context, 'Merged. $moved ${moved == 1 ? "entry" : "entries"} moved.');
    });
  }

  Future<void> _voidDuplicate(DuplicateEntryPair pair, String churchId) async {
    final actor = ref.read(churchUserProfileProvider).valueOrNull;
    if (actor == null) return;

    final ok = await selConfirm(
      context,
      title: 'Clear the duplicate?',
      message:
          'The later of the two is voided — it stays readable but counts toward '
          'nothing. The original is untouched.',
      confirmLabel: 'Clear duplicate',
    );
    if (!ok) return;

    await _run('voidDup', () async {
      await ref.read(entriesRepositoryProvider).voidEntries(
            churchId: churchId,
            entries: [pair.duplicate],
            actor: actor,
            reason: 'Duplicate of ${pair.original.id}',
          );
      if (!mounted) return;
      setState(() {
        _dupEntries = _dupEntries
            ?.where((p) => p.duplicate.id != pair.duplicate.id)
            .toList();
      });
      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: 'entry.void',
        entityType: 'entry',
        entityId: pair.duplicate.id,
        entitySnapshot: {
          'originalId': pair.original.id,
          'reason': 'Duplicate',
        },
      );
      if (!context.mounted) return;
      selNotice(
        context,
        'Duplicate cleared. Restore it from the entry if that was a mistake.',
      );
    });
  }
}

// ------------------------------------------------------------------ tool card

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.runLabel,
    required this.running,
    required this.onRun,
    this.result,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final String runLabel;
  final bool running;
  final VoidCallback onRun;
  final Widget? result;
  final String? progress;

  @override
  Widget build(BuildContext context) {
    return SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: Sel.warm),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: SelType.subtitleSm),
                    const SizedBox(height: SelSpace.x1),
                    Text(blurb, style: SelType.bodyMuted),
                  ],
                ),
              ),
              const SizedBox(width: SelSpace.x4),
              SelButton(
                label: running ? 'Working…' : runLabel,
                dense: true,
                onPressed: running ? null : onRun,
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: SelSpace.x3),
            Text(progress!, style: SelType.small),
          ],
          if (result != null) ...[
            const SizedBox(height: SelSpace.x4),
            const Divider(height: 1, color: Sel.border),
            const SizedBox(height: SelSpace.x4),
            result!,
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- results

class _TotalsResult extends StatelessWidget {
  const _TotalsResult({
    required this.report,
    required this.money,
    required this.onRepair,
    required this.repairing,
  });

  final TotalsAuditReport report;
  final String Function(num) money;
  final VoidCallback onRepair;
  final bool repairing;

  @override
  Widget build(BuildContext context) {
    if (report.isHealthy) {
      return Row(
        children: [
          const SelStatusMark(status: SelStatus.approved, label: 'All correct'),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Text(
              '${report.entriesScanned} entries checked. Every partner and '
              'period total matches.',
              style: SelType.bodyMuted,
            ),
          ),
        ],
      );
    }

    final rows = [...report.partnerDrift, ...report.periodDrift];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${report.issueCount} ${report.issueCount == 1 ? "total is" : "totals are"} '
          'wrong, out of ${report.entriesScanned} entries checked.',
          style: SelType.bodyMedium,
        ),
        const SizedBox(height: SelSpace.x3),
        SelLedger.builder(
          minWidth: 560,
          maxVirtualHeight: 320,
          columns: const [
            SelColumn('Record', flex: 3),
            SelColumn('Kind', fit: SelColFit.fixed, width: 90),
            SelColumn.numeric('Stored', width: 130),
            SelColumn.numeric('Should be', width: 130),
          ],
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final d = rows[i];
            return SelRow(
              cells: [
                SelCell.primary(d.name),
                SelCell.secondary(
                  d.kind == TotalsDriftKind.partner ? 'Partner' : 'Period',
                ),
                SelCell.numeric(money(d.stored), tone: SelTone.negative),
                SelCell.numeric(money(d.expected), tone: SelTone.positive),
              ],
            );
          },
        ),
        const SizedBox(height: SelSpace.x3),
        Align(
          alignment: Alignment.centerLeft,
          child: SelButton.cyan(
            label: repairing ? 'Correcting…' : 'Correct these totals',
            dense: true,
            onPressed: repairing ? null : onRepair,
          ),
        ),
      ],
    );
  }
}

class _DuplicatePartnersResult extends StatelessWidget {
  const _DuplicatePartnersResult({
    required this.pairs,
    required this.money,
    required this.onMerge,
    required this.busy,
  });

  final List<DuplicatePartnerPair> pairs;
  final String Function(num) money;
  final void Function(DuplicatePartnerPair pair, bool keepA) onMerge;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) {
      return const Row(
        children: [
          SelStatusMark(status: SelStatus.approved, label: 'None found'),
          SizedBox(width: SelSpace.x3),
          Text('No partner looks like a duplicate of another.'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${pairs.length} possible ${pairs.length == 1 ? "duplicate" : "duplicates"}. '
          'Choose which record to keep — the other is closed, not deleted.',
          style: SelType.bodyMuted,
        ),
        const SizedBox(height: SelSpace.x3),
        for (final p in pairs.take(20)) ...[
          Container(
            padding: const EdgeInsets.all(SelSpace.x3),
            decoration: BoxDecoration(
              color: Sel.canvas,
              borderRadius: BorderRadius.circular(SelRadius.card),
              border: Border.all(color: Sel.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.reason, style: SelType.small)),
                    if (p.confidence < 1.0)
                      Text(
                        'worth checking',
                        style: SelType.small.copyWith(color: Sel.warning),
                      ),
                  ],
                ),
                const SizedBox(height: SelSpace.x2),
                _MergeSide(
                  partner: p.a,
                  money: money,
                  onKeep: busy ? null : () => onMerge(p, true),
                ),
                const SizedBox(height: SelSpace.x2),
                _MergeSide(
                  partner: p.b,
                  money: money,
                  onKeep: busy ? null : () => onMerge(p, false),
                ),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x2),
        ],
        if (pairs.length > 20)
          Text(
            'Showing the first 20 of ${pairs.length}. Merge these, then run the '
            'check again.',
            style: SelType.small,
          ),
      ],
    );
  }
}

class _MergeSide extends StatelessWidget {
  const _MergeSide({
    required this.partner,
    required this.money,
    required this.onKeep,
  });

  final dynamic partner;
  final String Function(num) money;
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${partner.fullName}  ·  ${partner.memberId.isEmpty ? "no member ID" : partner.memberId}'
            '  ·  ${money(partner.totalApprovedAmount)} (${partner.entryCount})'
            '${partner.isActive ? "" : "  ·  inactive"}',
            style: SelType.bodyMuted,
          ),
        ),
        SelButton(
          label: 'Keep this one',
          kind: SelButtonKind.quiet,
          dense: true,
          onPressed: onKeep,
        ),
      ],
    );
  }
}

class _DuplicateEntriesResult extends StatelessWidget {
  const _DuplicateEntriesResult({
    required this.pairs,
    required this.money,
    required this.onVoid,
    required this.busy,
  });

  final List<DuplicateEntryPair> pairs;
  final String Function(num) money;
  final void Function(DuplicateEntryPair) onVoid;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) {
      return const Row(
        children: [
          SelStatusMark(status: SelStatus.approved, label: 'None found'),
          SizedBox(width: SelSpace.x3),
          Text('No gift appears to have been recorded twice.'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${pairs.length} ${pairs.length == 1 ? "gift looks" : "gifts look"} '
          'recorded twice. The earlier one is kept.',
          style: SelType.bodyMuted,
        ),
        const SizedBox(height: SelSpace.x3),
        SelLedger.builder(
          minWidth: 620,
          maxVirtualHeight: 360,
          // Partner cell is two lines (name, why it looks duplicated).
          rowExtent: kSelLedgerStackedRowExtent,
          columns: const [
            SelColumn('Partner', flex: 3),
            SelColumn.numeric('Amount', width: 130),
            SelColumn('Recorded', fit: SelColFit.fixed, width: 120),
            SelColumn('', fit: SelColFit.fixed, width: 140),
          ],
          itemCount: pairs.length,
          itemBuilder: (context, i) {
            final p = pairs[i];
            return SelRow(
              cells: [
                SelCell.stacked(
                  p.duplicate.partnerSnapshot['fullName']?.toString() ?? '—',
                  p.reason,
                ),
                SelCell.numeric(money(p.duplicate.amountCedis)),
                SelCell.secondary(
                  '${p.duplicate.dateGiven.day}/${p.duplicate.dateGiven.month}/'
                  '${p.duplicate.dateGiven.year}',
                ),
                SelButton(
                  label: 'Clear it',
                  kind: SelButtonKind.quiet,
                  dense: true,
                  onPressed: busy ? null : () => onVoid(p),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PartnerDataResult extends StatelessWidget {
  const _PartnerDataResult({
    required this.issues,
    required this.onFixCasing,
    required this.busy,
  });

  final List<PartnerDataIssue> issues;
  final VoidCallback onFixCasing;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const Row(
        children: [
          SelStatusMark(status: SelStatus.approved, label: 'All tidy'),
          SizedBox(width: SelSpace.x3),
          Text('Every partner has a member ID, a fellowship and a clean name.'),
        ],
      );
    }

    final casing = issues.where((i) => i.isAutoFixable).toList();
    final byKind = <PartnerIssueKind, int>{};
    for (final i in issues) {
      byKind[i.kind] = (byKind[i.kind] ?? 0) + 1;
    }

    String label(PartnerIssueKind k) => switch (k) {
      PartnerIssueKind.casing => 'Name or fellowship needs tidying',
      PartnerIssueKind.missingMemberId => 'No member ID',
      PartnerIssueKind.missingFellowship => 'No fellowship',
      PartnerIssueKind.duplicateMemberId => 'Member ID used twice',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in byKind.entries) ...[
          Row(
            children: [
              Expanded(child: Text(label(entry.key), style: SelType.bodyMuted)),
              Text('${entry.value}', style: SelType.bodyMedium),
            ],
          ),
          const SizedBox(height: SelSpace.x2),
        ],
        if (casing.isNotEmpty) ...[
          const SizedBox(height: SelSpace.x2),
          SelLedger.builder(
            minWidth: 460,
            maxVirtualHeight: 260,
            showCaptions: false,
            columns: const [SelColumn('Change', flex: 1)],
            itemCount: casing.length,
            itemBuilder: (context, i) =>
                SelRow(cells: [SelCell.secondary(casing[i].detail)]),
          ),
          const SizedBox(height: SelSpace.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: SelButton.cyan(
              label: busy
                  ? 'Tidying…'
                  : 'Tidy ${casing.length} ${casing.length == 1 ? "name" : "names"}',
              dense: true,
              onPressed: busy ? null : onFixCasing,
            ),
          ),
          const SizedBox(height: SelSpace.x2),
          Text(
            'Only casing is corrected. A missing member ID or fellowship is a '
            'decision for you, not a repair.',
            style: SelType.small,
          ),
        ],
      ],
    );
  }
}
