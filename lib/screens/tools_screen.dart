import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
import '../features/activity/activity_log_helper.dart';
import '../design/seline.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/totals/totals_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/maintenance/data/maintenance_repository.dart';
import '../features/maintenance/domain/data_health.dart';
import '../features/maintenance/domain/totals_audit.dart';
import '../features/maintenance/providers/duplicate_health_provider.dart';
import '../features/operations/recent_changes_card.dart';
import '../features/operations/record_ops_repository.dart';
import '../features/partners/domain/partner.dart';
import '../features/partners/providers/partners_providers.dart';
import '../core/errors/plain_error.dart';

/// Tools — the repairs a giving ledger needs after a few years of use.
///
/// Every one of these follows the same shape, and it matters: **scan, show,
/// then ask**. None of them changes anything on arrival. A church's giving
/// records are about real people and real money, so a tool that tidied on
/// sight would be worse than no tool — the point is to make a problem
/// visible and let someone decide.
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key, this.initialTool});

  /// Opens on this tool, e.g. `changes` from a summary's See it in Changes.
  final String? initialTool;

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  String? _running;

  /// The tool open on the right.
  late String _tool = widget.initialTool ?? 'dupPartners';

  TotalsAuditReport? _totals;
  List<DuplicatePartnerPair>? _dupPartners;
  List<DuplicateEntryPair>? _dupEntries;
  List<PartnerDataIssue>? _partnerIssues;
  int _scanned = 0;

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    // Only a pastor sees figures here. Staff and admins repair the book
    // without seeing what anyone gave.
    final pastor = idx?.isPastor ?? false;
    final realMoney = ref.watch(churchMoneyFormatProvider);
    final String Function(num) money = pastor ? realMoney : _noFigure;
    final canManage = idx?.canUseTools ?? false;

    if (!canManage) {
      return const SelPageBody(
        maxWidth: 640,
        children: [
          SelEmpty(
            title: 'Not your tools',
            message:
                'Repairs to the ledger are done by a pastor, an admin, or staff.',
          ),
        ],
      );
    }

    final cards = <String, Widget>{
        'totals': _ToolCard(
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
                    final fixable = all.where((d) => d.name != '(missing record)').length;
                    var n = 0;
                    await runWithProgress(
                      context,
                      title: 'Putting $fixable ${fixable == 1 ? 'total' : 'totals'} right',
                      run: (p) async {
                        p.start(fixable);
                        n = await ref.read(maintenanceRepositoryProvider).repairTotals(
                              churchId: idx!.churchId,
                              drift: all,
                              onEach: (name) => p.tick('$name · recounted from its entries'),
                            );
                        return SelSummary(
                          title: '$n ${n == 1 ? 'total' : 'totals'} put right',
                          numbers: [('$n', 'corrected'), ('${all.length - fixable}', 'records missing')],
                          lines: const [SelSummaryLine('Each total now matches its entries', detail: 'Nothing about the entries themselves changed.')],
                        );
                      },
                    );
                    if (!context.mounted) return;
                    setState(() => _totals = null);
                    ref.invalidate(partnersStreamProvider(false));
                    invalidateEntryDerivedData(ref);
                    await logPillrActivity(
                      ref,
                      churchId: idx!.churchId,
                      action: 'totals.repair',
                      entityType: 'church',
                      entityId: idx.churchId,
                      entitySnapshot: {'corrected': n},
                    );
                  }),
                  repairing: _running == 'repair',
                ),
        ),

        'separate': _SeparateCard(
          busy: _running == 'separate',
          onSeparate: (id) => _separate(id, idx!.churchId),
        ),

        'dupPartners': _ToolCard(
          icon: LucideIcons.users,
          title: 'Merge duplicate partners',
          blurb:
              'The same person entered twice — usually once by hand and once by '
              'an import. Compares member ID, phone (in any format), email and '
              'name — titles, word order, initials and small typos included.'
              '${_nightlyNote(ref.watch(duplicateHealthProvider).valueOrNull)}',
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
                  found: groupDuplicates(_dupPartners!),
                  money: money,
                  onMerge: (pair, keepA) => _merge(pair, keepA, idx!.churchId),
                  onMergeGroup: (g, keep) =>
                      _mergeGroup(g, keep, idx!.churchId),
                  onDismiss: (pair) => _dismiss(pair, idx!.churchId),
                  onDismissGroup: (g) => _dismissGroup(g, idx!.churchId),
                  busy: _running == 'merge' || _running == 'dismiss',
                ),
        ),

        'dupEntries': _ToolCard(
          icon: LucideIcons.copy,
          title: 'Find duplicate entries',
          blurb:
              'The same entry recorded twice — same partner, arm, period, date '
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
            // Staff check only the entries they recorded themselves.
            final mine = idx.isStaff
                ? [
                    for (final p in pairs)
                      if (p.duplicate.createdBy == idx.uid && p.original.createdBy == idx.uid) p,
                  ]
                : pairs;
            if (mounted) setState(() => _dupEntries = mine);
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

        'partnerData': _ToolCard(
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
                    await logPillrActivity(
                      ref,
                      churchId: idx.churchId,
                      action: 'partner.tidy',
                      entityType: 'partner',
                      entitySnapshot: {'corrected': n},
                    );
                    if (!context.mounted) return;
                    selNotice(
                      context,
                      'Corrected $n ${n == 1 ? "name" : "names"}.',
                    );
                  }),
                ),
        ),
    };

    final dupes = ref.watch(duplicateHealthProvider).valueOrNull?.open ?? 0;
    final tools = [
      ('dupPartners', 'Possible duplicates', 'The same person on the book twice', dupes),
      // Entries are read by pastors and, their own, by staff; totals by
      // pastors alone. An admin tidies partners and merges.
      if (!(idx?.isAdmin ?? false))
        ('dupEntries', 'Giving entered twice', 'Same partner, amount and day', _dupEntries?.length ?? 0),
      ('partnerData', 'Names and fellowships', 'Capitals and missing details', _partnerIssues?.length ?? 0),
      if (pastor) ('totals', 'Totals', 'Add the entries up again', 0),
      ('separate', 'Take someone out of a merge', 'By their old member ID', 0),
      ('move', 'Move people', 'Between fellowships, one or many', 0),
      ('changes', 'Changes', 'Undo a move, merge or rename', 0),
    ];
    final list = SelCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (id, title, note, n) in tools)
            Material(
              color: id == _tool ? Sel.skyTint : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => id == 'move' ? context.go('/tools/move') : setState(() => _tool = id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: SelType.bodyMedium),
                            Text(note, style: SelType.small),
                          ],
                        ),
                      ),
                      if (n > 0) SelCountTag(label: '$n', emphasised: true),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tool == 'changes')
          const RecentChangesCard()
        else ...[
          cards[_tool] ?? cards['dupPartners']!,
          const SizedBox(height: SelSpace.x4),
          const RecentChangesCard(),
        ],
      ],
    );

    return SelPageBody(
      children: [
        const SelPageTitle(
          title: 'Tools',
          subtitle:
              'Checks and repairs for the book. Nothing changes until you say '
              'so, and every repair can be undone.',
        ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 900
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [list, const SizedBox(height: SelSpace.x4), detail],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 280, child: list),
                    const SizedBox(width: SelSpace.x4),
                    Expanded(child: detail),
                  ],
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
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _merge(DuplicatePartnerPair pair, bool keepA, String churchId) =>
      _mergeRecords(keepA ? pair.a : pair.b, [
        keepA ? pair.b : pair.a,
      ], churchId);

  Future<void> _mergeGroup(
    DuplicateGroup group,
    Partner keep,
    String churchId,
  ) => _mergeRecords(keep, [
    for (final p in group.partners)
      if (p.id != keep.id) p,
  ], churchId);

  /// One person, several records: [keep] stays, the rest close. The person
  /// gets a new member ID and keeps every old one.
  Future<void> _mergeRecords(
    Partner keep,
    List<Partner> others,
    String churchId,
  ) async {
    await _run('merge', () async {
      final pastor = ref.read(userChurchIndexProvider).valueOrNull?.isPastor ?? false;
      final repo = ref.read(maintenanceRepositoryProvider);
      // Only a pastor reads every entry, so only a pastor is told how many
      // move and for how much. The server moves all of them either way.
      final entries = pastor
          ? await repo.entriesForPartners(churchId, [keep.id, for (final o in others) o.id])
          : const <PartnershipEntry>[];
      final otherIds = {for (final o in others) o.id};
      final moving = entries
          .where((e) => otherIds.contains(e.partnerId))
          .length;
      var total = 0.0;
      for (final e in entries) {
        if (e.countsTowardTotals) total += e.amountCedis;
      }
      final oldIds = [
        if (keep.memberId.isNotEmpty) keep.memberId,
        for (final o in others)
          if (o.memberId.isNotEmpty) o.memberId,
      ];
      final money = ref.read(churchMoneyFormatProvider);

      if (!mounted) return;
      final ok = await selConfirm(
        context,
        title: others.length == 1
            ? 'Make these one person?'
            : 'Make these ${others.length + 1} records one person?',
        message:
            '${keep.fullName} stays. '
            '${others.length == 1 ? "The other record closes" : "The other ${others.length} records close"}'
            ' — nothing is deleted.\n\n'
            '${pastor ? '• $moving ${moving == 1 ? "entry moves" : "entries move"} to ${keep.fullName}. Their total becomes ${money(total)}.\n' : '• All their giving moves to ${keep.fullName}.\n'}'
            '• Every phone number and email from these records stays with '
            '${keep.fullName}.\n'
            '• ${keep.fullName} gets a new member ID. The old IDs '
            '(${oldIds.join(", ")}) stay with them, so old sheets and receipts '
            'still find them.\n\n'
            'You can undo this, or later take out any one record by its old ID.',
        confirmLabel: 'Make one person',
      );
      if (!ok) return;

      // The count the person just confirmed: if an entry lands on any of these
      // records before the server runs, it refuses rather than move a
      // different set.
      if (!mounted) return;
      await runWithProgress(
        context,
        title: 'Making ${keep.fullName} one person',
        subtitle: 'Pillr does this on the server; keep this page open.',
        steps: [
          'Checking the ${others.length + 1} records',
          'Moving their giving and contact details to ${keep.fullName}',
          'Giving ${keep.fullName} one member ID',
        ],
        run: (p) async {
          final r = await runServerSteps(
            p,
            () => ref.read(recordOpsRepositoryProvider).partnerMerge(
                  churchId: churchId,
                  keepId: keep.id,
                  absorbIds: [for (final o in others) o.id],
                  expectEntries: pastor ? moving : null,
                ),
          );
          return SelSummary(
            title: '${keep.fullName} is one person now',
            numbers: [
              (r.newMemberId, 'new member ID'),
              ('${r.moved}', '${r.moved == 1 ? 'entry' : 'entries'} moved'),
              ('${others.length}', '${others.length == 1 ? 'record' : 'records'} closed'),
            ],
            lines: [
              if (r.filled.isNotEmpty) SelSummaryLine('${r.filled.join(' and ')} copied over'),
              SelSummaryLine('The old IDs still find ${keep.fullName}', detail: oldIds.join(', ')),
            ],
          );
        },
      );
      if (!mounted) return;
      setState(() => _dupPartners = null);
      ref.invalidate(partnersStreamProvider(false));
      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
    });
  }

  Future<void> _separate(String memberId, String churchId) async {
    final id = memberId.trim().toUpperCase();
    if (id.isEmpty) return;
    final ok = await selConfirm(
      context,
      title: 'Take $id out of its merge?',
      message:
          'The record with ID $id opens again with its own giving. Everyone '
          'else stays merged. You can undo this too.',
      confirmLabel: 'Take it out',
    );
    if (!ok) return;
    await _run('separate', () async {
      await runWithProgress(
        context,
        title: 'Taking $id out of its merge',
        steps: ['Finding $id', 'Moving its giving back to it', 'Opening its record again'],
        run: (p) async {
          final r = await runServerSteps(
            p,
            () => ref.read(recordOpsRepositoryProvider).partnerUnmerge(churchId: churchId, memberId: id),
          );
          return SelSummary(
            title: '$id is its own record again',
            numbers: [('${r.moved}', '${r.moved == 1 ? 'entry' : 'entries'} went back to it')],
          );
        },
      );
      ref.invalidate(partnersStreamProvider(false));
      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
    });
  }

  Future<void> _dismissGroup(DuplicateGroup group, String churchId) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    await _run('dismiss', () async {
      final repo = ref.read(maintenanceRepositoryProvider);
      for (final pair in group.pairs) {
        await repo.dismissDuplicatePair(
          churchId: churchId,
          pair: pair,
          uid: uid,
        );
      }
      if (!mounted) return;
      final keys = {for (final p in group.pairs) p.key};
      setState(() {
        _dupPartners = _dupPartners
            ?.where((p) => !keys.contains(p.key))
            .toList();
      });
    });
  }

  Future<void> _dismiss(DuplicatePartnerPair pair, String churchId) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    await _run('dismiss', () async {
      await ref
          .read(maintenanceRepositoryProvider)
          .dismissDuplicatePair(churchId: churchId, pair: pair, uid: uid);
      if (!mounted) return;
      setState(() {
        _dupPartners = _dupPartners?.where((p) => p.key != pair.key).toList();
      });
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
      await ref
          .read(entriesRepositoryProvider)
          .voidEntries(
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
        entitySnapshot: {'originalId': pair.original.id, 'reason': 'Duplicate'},
      );
      if (!mounted) return;
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
    required this.found,
    required this.money,
    required this.onMerge,
    required this.onMergeGroup,
    required this.onDismiss,
    required this.onDismissGroup,
    required this.busy,
  });

  final ({List<DuplicateGroup> groups, List<DuplicatePartnerPair> pairs}) found;
  final String Function(num) money;
  final void Function(DuplicatePartnerPair pair, bool keepA) onMerge;
  final void Function(DuplicateGroup group, Partner keep) onMergeGroup;
  final void Function(DuplicatePartnerPair pair) onDismiss;
  final void Function(DuplicateGroup group) onDismissGroup;
  final bool busy;

  List<DuplicatePartnerPair> get pairs => found.pairs;

  static String bandLabel(DuplicateBand b) => switch (b) {
    DuplicateBand.almostCertain => 'Almost certainly the same',
    DuplicateBand.likely => 'Likely the same',
    DuplicateBand.check => 'Worth checking',
  };

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty && found.groups.isEmpty) {
      return const Row(
        children: [
          SelStatusMark(status: SelStatus.approved, label: 'None found'),
          SizedBox(width: SelSpace.x3),
          Expanded(
            child: Text('No partner looks like a duplicate of another.'),
          ),
        ],
      );
    }

    final counts = <DuplicateBand, int>{};
    for (final p in pairs) {
      counts[p.band] = (counts[p.band] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in found.groups) ...[
          _GroupCase(
            group: g,
            money: money,
            busy: busy,
            onKeep: (keep) => onMergeGroup(g, keep),
            onDismiss: () => onDismissGroup(g),
          ),
          const SizedBox(height: SelSpace.x2),
        ],
        if (found.groups.isNotEmpty && pairs.isNotEmpty)
          const SizedBox(height: SelSpace.x3),
        if (pairs.isNotEmpty)
          Text(
            '${pairs.length} possible ${pairs.length == 1 ? "duplicate" : "duplicates"}'
            ' — ${[for (final b in DuplicateBand.values)
              if ((counts[b] ?? 0) > 0) '${counts[b]} ${bandLabel(b).toLowerCase()}'].join(', ')}. '
            'Choose which record to keep — the other is closed, not deleted. '
            'If they are two people, say so and the pair is not shown again.',
            style: SelType.bodyMuted,
          ),
        const SizedBox(height: SelSpace.x3),
        for (final p in pairs.take(30)) ...[
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
                    const SizedBox(width: SelSpace.x2),
                    Text(
                      bandLabel(p.band),
                      style: SelType.small.copyWith(
                        color: p.band == DuplicateBand.almostCertain
                            ? Sel.success
                            : Sel.warning,
                      ),
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
                const SizedBox(height: SelSpace.x2),
                Align(
                  alignment: Alignment.centerRight,
                  child: SelButton(
                    label: 'Not the same person',
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: busy ? null : () => onDismiss(p),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x2),
        ],
        if (pairs.length > 30)
          Text(
            'Showing the first 30 of ${pairs.length}, strongest first. Settle '
            'these, then run the check again.',
            style: SelType.small,
          ),
      ],
    );
  }
}

/// Three or more records that are one person. Pick the one to keep.
class _GroupCase extends StatelessWidget {
  const _GroupCase({
    required this.group,
    required this.money,
    required this.busy,
    required this.onKeep,
    required this.onDismiss,
  });

  final DuplicateGroup group;
  final String Function(num) money;
  final bool busy;
  final void Function(Partner keep) onKeep;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final reasons = {
      for (final p in group.pairs) ...p.reasons,
    }.take(5).join(' · ');
    return Container(
      padding: const EdgeInsets.all(SelSpace.x3),
      decoration: BoxDecoration(
        color: Sel.canvas,
        borderRadius: BorderRadius.circular(SelRadius.card),
        border: Border.all(color: Sel.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${group.partners.length} records look like one person',
            style: SelType.bodyMedium,
          ),
          Text(reasons, style: SelType.small),
          const SizedBox(height: SelSpace.x2),
          Text(
            'Pick the record to keep. The others close and their giving moves to it.',
            style: SelType.bodyMuted,
          ),
          const SizedBox(height: SelSpace.x2),
          for (final p in group.partners) ...[
            _MergeSide(
              partner: p,
              money: money,
              onKeep: busy ? null : () => onKeep(p),
            ),
            const SizedBox(height: SelSpace.x2),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: SelButton(
              label: 'These are different people',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: busy ? null : onDismiss,
            ),
          ),
        ],
      ),
    );
  }
}

/// Take one record back out of a merge by its old member ID.
class _SeparateCard extends StatefulWidget {
  const _SeparateCard({required this.busy, required this.onSeparate});

  final bool busy;
  final void Function(String memberId) onSeparate;

  @override
  State<_SeparateCard> createState() => _SeparateCardState();
}

class _SeparateCardState extends State<_SeparateCard> {
  final _id = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.split, size: 18, color: Sel.warm),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Take a record out of a merge',
                      style: SelType.subtitleSm,
                    ),
                    const SizedBox(height: SelSpace.x1),
                    Text(
                      'Merged two people by mistake? Type the old member ID '
                      'of the one to take out. It opens again with its own '
                      'giving; the rest stay merged.',
                      style: SelType.bodyMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x3),
          Row(
            children: [
              Expanded(
                child: SelField(
                  controller: _id,
                  hint: 'Old member ID, e.g. ACC682216',
                ),
              ),
              const SizedBox(width: SelSpace.x3),
              SelButton(
                label: widget.busy ? 'Working…' : 'Take out',
                dense: true,
                onPressed: widget.busy
                    ? null
                    : () => widget.onSeparate(_id.text),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One side of a suspected pair, with everything needed to tell them apart.
class _MergeSide extends ConsumerWidget {
  const _MergeSide({
    required this.partner,
    required this.money,
    required this.onKeep,
  });

  final Partner partner;
  final String Function(num) money;
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = partner;
    final totals = ref.watch(partnerTotalsProvider).valueOrNull?[p.id] ?? StoredTotals.zero;
    final details = [
      p.memberId.isEmpty ? 'no member ID' : p.memberId,
      if (p.fellowship.trim().isNotEmpty) p.fellowship,
      if ((p.phone ?? '').trim().isNotEmpty) p.phone!.trim(),
      if ((p.email ?? '').trim().isNotEmpty) p.email!.trim(),
      // Pastors see what each record holds; others see nothing of it.
      if (money(0) != _noFigure(0)) '${money(totals.cedis)} (${totals.count})',
      if (!p.isActive) 'inactive',
    ];
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.fullName, style: SelType.bodyMedium),
              Text(details.join('  ·  '), style: SelType.small),
            ],
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
          Text('No entry appears to have been recorded twice.'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${pairs.length} ${pairs.length == 1 ? "entry looks" : "entries look"} '
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

/// "Last night's check: …" under the duplicates tool, or nothing before the
/// first nightly run.
String _nightlyNote(DuplicateHealth? h) {
  if (h == null) return '';
  if (h.open == 0) return '\n\nLast night\'s check found nothing to merge.';
  final groups = h.groups == 0
      ? ''
      : ', including ${h.groups} ${h.groups == 1 ? "person" : "people"} entered 3 or more times';
  return '\n\nLast night\'s check found ${h.open} likely '
      '${h.open == 1 ? "duplicate" : "duplicates"}$groups. Run the check to see them.';
}

/// What a figure shows to someone who may not see figures.
String _noFigure(num _) => '—';

