import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
import '../features/activity/activity_log_helper.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/fellowships/fellowship_match.dart';
import '../features/fellowships/fellowship_providers.dart';
import '../features/operations/recent_changes_card.dart';
import '../features/operations/record_ops_repository.dart';
import '../features/partners/domain/partner.dart';
import '../features/partners/providers/partners_providers.dart';
import '../core/errors/plain_error.dart';

/// Jakob: same page as the directory. Fitts: labeled Create. Hick: one
/// confirm per tool. Peak-end: the confirm names who moves. Tesler: we
/// rewrite partners; the pastor names the group. Von Restorff: one filled
/// action. Occam: catalog on church settings. Motion: press/focus only.
///
/// Move accepts one partner or many — the write already batches.
class FellowshipManageView extends ConsumerStatefulWidget {
  const FellowshipManageView({super.key});

  @override
  ConsumerState<FellowshipManageView> createState() =>
      _FellowshipManageViewState();
}

class _FellowshipManageViewState extends ConsumerState<FellowshipManageView> {
  final _selected = <String>{};
  String _query = '';
  bool _busy = false;

  List<String> get _known => ref.read(knownFellowshipsProvider);

  /// Runs [op] and reports its notice. [log] is for the one change made
  /// from the app (create); the server logs everything else itself.
  Future<void> _run(
    Future<String> Function() op, {
    Future<void> Function()? log,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final done = await op();
      if (log != null) {
        try {
          await log();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _selected.clear());
      selNotice(context, done, kind: SelNoticeKind.success);
    } catch (e) {
      if (!mounted) return;
      selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = await _askName(
      title: 'New fellowship',
      hint: 'Campus A',
      confirm: 'Create',
    );
    if (name == null || name.isEmpty) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    final catalog =
        ref.read(churchSettingsProvider).valueOrNull?.fellowshipNames ??
        const [];
    final partners =
        ref.read(partnersStreamProvider(false)).valueOrNull ?? const [];
    await _run(
      () async {
        await ref
            .read(fellowshipOpsProvider)
            .create(
              churchId: idx.churchId,
              name: name,
              catalog: catalog,
              partnerFellowships: partners.map((p) => p.fellowship),
            );
        return 'Created $name';
      },
      log: () => logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'fellowship.create',
        entityType: 'fellowship',
        entitySnapshot: {'name': name},
      ),
    );
  }

  Future<void> _rename(String from) async {
    final to = await _askName(
      title: 'Rename $from',
      hint: from,
      initial: from,
      confirm: 'Rename',
    );
    if (to == null || to.isEmpty || fellowshipNamesMatch(from, to)) return;
    await _applyMerge('rename', [from], to, 'Renamed to $to');
  }

  Future<void> _dissolve(String from) async {
    final others = [
      for (final n in _known)
        if (!fellowshipNamesMatch(n, from)) n,
    ];
    if (others.isEmpty) {
      selNotice(
        context,
        'Create another fellowship first, then dissolve into it.',
      );
      return;
    }
    final into = await _pickExisting(
      title: 'Dissolve $from into',
      options: others,
    );
    if (into == null) return;
    final ok = await _confirm(
      title: 'Dissolve $from?',
      body: 'Everyone in $from moves to $into. $from leaves the list.',
      confirm: 'Dissolve',
    );
    if (ok != true) return;
    await _applyMerge('dissolve', [from], into, 'Moved into $into');
  }

  Future<void> _moveFromPicker({String? fromName}) async {
    final partners =
        ref.read(partnersStreamProvider(false)).valueOrNull ?? const [];
    final picked = await _pickPartners(
      title: fromName == null ? 'Move partners' : 'Move people from $fromName',
      partners: [
        for (final p in partners)
          if (fromName == null || fellowshipNamesMatch(p.fellowship, fromName))
            p,
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _movePeople(picked);
  }

  Future<void> _movePeople(List<Partner> moving) async {
    if (moving.isEmpty) return;
    final others = [
      for (final n in _known)
        if (moving.any((p) => !fellowshipNamesMatch(n, p.fellowship))) n,
    ];
    if (others.isEmpty) {
      selNotice(
        context,
        'Create another fellowship first, then move someone into it.',
      );
      return;
    }
    final into = await _pickExisting(
      title: moving.length == 1
          ? 'Move ${moving.first.fullName} to'
          : 'Move ${moving.length} partners to',
      options: others,
    );
    if (into == null || !mounted) return;
    final from = fellowshipMoveFromLabel(moving.map((p) => p.fellowship));
    final ok = await _confirm(
      title: moving.length == 1
          ? 'Move ${moving.first.fullName}?'
          : 'Move ${moving.length} partners?',
      body: fellowshipMoveConfirmBody(
        names: [for (final p in moving) p.fullName],
        from: from,
        into: into,
      ),
      confirm: 'Move',
    );
    if (ok != true || !mounted) return;
    final done = moving.length == 1
        ? 'Moved ${moving.first.fullName} to $into'
        : 'Moved ${moving.length} partners to $into';
    await _applyMove(moving, into, done);
  }

  Future<void> _showMembers(String name) async {
    final partners =
        ref.read(partnersStreamProvider(false)).valueOrNull ?? const [];
    final members = [
      for (final p in partners)
        if (fellowshipNamesMatch(p.fellowship, name)) p,
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (members.isEmpty) {
      selNotice(context, 'Nobody is in $name yet.');
      return;
    }
    if (!mounted) return;
    final picked = <String>{};
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          void toggle(String id, bool? on) {
            setLocal(() {
              if (on == true) {
                picked.add(id);
              } else {
                picked.remove(id);
              }
            });
          }

          return SelDialog(
            title: name,
            subtitle:
                '${members.length} '
                '${members.length == 1 ? 'partner' : 'partners'}',
            width: 520,
            actions: [
              SelButton(
                label: 'Close',
                kind: SelButtonKind.quiet,
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (picked.isNotEmpty)
                SelButton.cyan(
                  label: picked.length == 1
                      ? 'Move 1 partner'
                      : 'Move ${picked.length} partners',
                  onPressed: _busy
                      ? null
                      : () {
                          final moving = [
                            for (final p in members)
                              if (picked.contains(p.id)) p,
                          ];
                          Navigator.of(context).pop();
                          _movePeople(moving);
                        },
                ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (members.length > 1)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                      value: picked.length == members.length,
                      onChanged: _busy
                          ? null
                          : (v) => setLocal(() {
                              if (v == true) {
                                picked.addAll(members.map((p) => p.id));
                              } else {
                                picked.clear();
                              }
                            }),
                    ),
                    title: Text('Select all', style: SelType.bodyMedium),
                    onTap: _busy
                        ? null
                        : () => setLocal(() {
                            if (picked.length == members.length) {
                              picked.clear();
                            } else {
                              picked.addAll(members.map((p) => p.id));
                            }
                          }),
                  ),
                for (final p in members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                      value: picked.contains(p.id),
                      onChanged: _busy ? null : (v) => toggle(p.id, v),
                    ),
                    title: Text(p.fullName, style: SelType.body),
                    subtitle: p.memberId.trim().isEmpty
                        ? null
                        : Text(p.memberId, style: SelType.small),
                    onTap: _busy
                        ? null
                        : () => toggle(p.id, !picked.contains(p.id)),
                    trailing: SelButton(
                      label: 'Move',
                      kind: SelButtonKind.quiet,
                      dense: true,
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              _movePeople([p]);
                            },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _mergeSelected() async {
    final names = _selected.toList()..sort();
    if (names.length < 2) {
      selNotice(context, 'Select two or more fellowships to merge.');
      return;
    }
    final to = await _askName(
      title: 'Merge into',
      hint: names.first,
      initial: names.first,
      confirm: 'Merge',
      help:
          'Partners in ${names.join(', ')} move into this name. '
          'Use an existing name or type a new one.',
    );
    if (to == null || to.isEmpty) return;
    final ok = await _confirm(
      title: 'Merge these fellowships?',
      body: '${names.join(', ')} become $to. The old names leave the list.',
      confirm: 'Merge',
    );
    if (ok != true) return;
    await _applyMerge('merge', names, to, 'Merged into $to');
  }

  /// Merge, rename and dissolve all run as one server change. The count of
  /// active partners this screen shows is sent along: if someone else has
  /// changed the groups since, the server refuses rather than guess.
  Future<void> _applyMerge(
    String kind,
    List<String> from,
    String to,
    String done,
  ) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    final partners =
        ref.read(partnersStreamProvider(false)).valueOrNull ?? const [];
    final fromKeys = {for (final n in from) n.trim().toLowerCase()}
      ..remove(to.trim().toLowerCase());
    final expect = partners
        .where((p) => fromKeys.contains(p.fellowship.trim().toLowerCase()))
        .length;
    await _run(() async {
      final r = await ref.read(recordOpsRepositoryProvider).fellowshipChange(
        churchId: idx.churchId,
        kind: kind,
        fromNames: from,
        toName: to,
        expectActive: expect,
      );
      if (r.opId == null) return 'Nothing to change — everyone was already there.';
      return fellowshipChangeNotice(done, r.moved, r.inactiveMoved);
    });
  }

  Future<void> _applyMove(
    List<Partner> moving,
    String to,
    String done,
  ) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    await _run(() async {
      final r = await ref.read(recordOpsRepositoryProvider).fellowshipChange(
        churchId: idx.churchId,
        kind: 'move',
        partnerIds: [for (final p in moving) p.id],
        toName: to,
      );
      if (r.opId == null) return 'Nothing to change — everyone was already there.';
      return fellowshipChangeNotice(done, r.moved, r.inactiveMoved);
    });
  }

  Future<String?> _askName({
    required String title,
    required String hint,
    required String confirm,
    String? initial,
    String? help,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => SelDialog(
        title: title,
        width: 460,
        scrollable: false,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.of(context).pop(),
          ),
          SelButton.cyan(
            label: confirm,
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (help != null) ...[
              Text(help, style: SelType.bodyMuted),
              const SizedBox(height: SelSpace.x4),
            ],
            SelField(
              controller: controller,
              label: 'Name',
              hint: hint,
              autofocus: true,
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<List<Partner>?> _pickPartners({
    required String title,
    required List<Partner> partners,
  }) {
    var query = '';
    final selected = <String>{};
    final sorted = [...partners]
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return showDialog<List<Partner>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final rows = [
            for (final p in sorted)
              if (query.isEmpty ||
                  p.fullName.toLowerCase().contains(query) ||
                  p.memberId.toLowerCase().contains(query) ||
                  p.fellowship.toLowerCase().contains(query))
                p,
          ];
          void toggle(String id) {
            setLocal(() {
              if (selected.contains(id)) {
                selected.remove(id);
              } else {
                selected.add(id);
              }
            });
          }

          return SelDialog(
            title: title,
            subtitle: 'Select who moves. Search to narrow the list.',
            width: 520,
            actions: [
              SelButton(
                label: 'Cancel',
                kind: SelButtonKind.quiet,
                onPressed: () => Navigator.of(context).pop(),
              ),
              SelButton.cyan(
                label: selected.isEmpty
                    ? 'Move'
                    : selected.length == 1
                    ? 'Move 1 partner'
                    : 'Move ${selected.length} partners',
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop([
                        for (final p in sorted)
                          if (selected.contains(p.id)) p,
                      ]),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelField(
                  hint: 'Name, member ID, or fellowship',
                  prefixIcon: LucideIcons.search,
                  autofocus: true,
                  onChanged: (v) =>
                      setLocal(() => query = v.trim().toLowerCase()),
                ),
                const SizedBox(height: SelSpace.x3),
                if (rows.isEmpty)
                  Text('No matches.', style: SelType.bodyMuted)
                else
                  for (final p in rows.take(40))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                        value: selected.contains(p.id),
                        onChanged: (_) => toggle(p.id),
                      ),
                      title: Text(p.fullName, style: SelType.body),
                      subtitle: Text(
                        [
                          if (p.memberId.trim().isNotEmpty) p.memberId,
                          p.fellowship.trim().isEmpty
                              ? 'No fellowship'
                              : p.fellowship,
                        ].join(' · '),
                        style: SelType.small,
                      ),
                      onTap: () => toggle(p.id),
                    ),
                if (rows.length > 40)
                  Text(
                    'and ${rows.length - 40} more — keep typing to narrow it.',
                    style: SelType.small,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String?> _pickExisting({
    required String title,
    required List<String> options,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => SelDialog(
        title: title,
        width: 460,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final n in options)
              ListTile(
                title: Text(n, style: SelType.body),
                onTap: () => Navigator.of(context).pop(n),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => SelDialog(
        title: title,
        width: 460,
        scrollable: false,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SelButton.cyan(
            label: confirm,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        child: Text(body, style: SelType.body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final canEdit = idx?.canManageFellowships ?? false;
    final known = ref.watch(knownFellowshipsProvider);
    final partners =
        ref.watch(partnersStreamProvider(false)).valueOrNull ?? const [];
    final counts = <String, int>{};
    for (final p in partners) {
      final key = p.fellowship.trim().toLowerCase();
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final rows = [
      for (final name in known)
        if (_query.isEmpty || name.toLowerCase().contains(_query)) name,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (canEdit)
              SelButton(
                label: 'Create fellowship',
                icon: LucideIcons.plus,
                onPressed: _busy ? null : _create,
              ),
            if (canEdit) ...[
              const SizedBox(width: SelSpace.x2),
              SelButton(
                label: 'Move partners',
                onPressed: _busy ? null : () => _moveFromPicker(),
              ),
            ],
            if (canEdit && _selected.length >= 2) ...[
              const SizedBox(width: SelSpace.x2),
              SelButton.cyan(
                label: 'Merge selected',
                onPressed: _busy ? null : _mergeSelected,
              ),
            ],
            const Spacer(),
            SizedBox(
              width: 240,
              child: SelField(
                hint: 'Search fellowship',
                prefixIcon: LucideIcons.search,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
          ],
        ),
        const SizedBox(height: SelSpace.x4),
        if (rows.isEmpty)
          SelCard(
            child: SelEmpty(
              title: _query.isEmpty ? 'No fellowships yet' : 'No matches',
              message: _query.isEmpty
                  ? 'Create a group, or they appear when partners are assigned.'
                  : 'Nothing matches “$_query”.',
              icon: LucideIcons.users,
            ),
          )
        else
          SelLedger(
            minWidth: 760,
            columns: [
              if (canEdit) const SelColumn('', fit: SelColFit.fixed, width: 36),
              const SelColumn('Fellowship', flex: 3),
              const SelColumn.numeric('Partners', width: 110),
              if (canEdit) const SelColumn('Tools', flex: 3),
            ],
            rows: [
              for (final name in rows)
                SelRow(
                  cells: [
                    if (canEdit)
                      Checkbox(
                        value: _selected.contains(name),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _selected.add(name);
                                } else {
                                  _selected.remove(name);
                                }
                              }),
                      ),
                    SelCell.primary(name),
                    SelCell.numeric('${counts[name.toLowerCase()] ?? 0}'),
                    if (canEdit)
                      Wrap(
                        spacing: SelSpace.x2,
                        children: [
                          SelButton(
                            label: 'Members',
                            kind: SelButtonKind.quiet,
                            dense: true,
                            onPressed: _busy ? null : () => _showMembers(name),
                          ),
                          SelButton(
                            label: 'Rename',
                            kind: SelButtonKind.quiet,
                            dense: true,
                            onPressed: _busy ? null : () => _rename(name),
                          ),
                          SelButton(
                            label: 'Dissolve',
                            kind: SelButtonKind.quiet,
                            dense: true,
                            onPressed: _busy ? null : () => _dissolve(name),
                          ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        if (canEdit) ...[
          const SizedBox(height: SelSpace.x6),
          const RecentChangesCard(
            kindPrefix: 'fellowship.',
            blurb:
                'Merges, moves, renames and dissolves. Undo puts everyone back '
                'in the group they were in — inactive partners too — and brings '
                'back any name the change removed.',
          ),
        ],
      ],
    );
  }
}

String fellowshipMoveFromLabel(Iterable<String> fellowships) {
  final froms = {
    for (final f in fellowships) f.trim().isEmpty ? 'no fellowship' : f.trim(),
  };
  if (froms.isEmpty) return 'no fellowship';
  if (froms.length == 1) return froms.first;
  return froms.join(' · ');
}

String fellowshipMoveConfirmBody({
  required List<String> names,
  required String from,
  required String into,
}) {
  if (names.length == 1) {
    return '${names.first} leaves $from and joins $into.';
  }
  if (from.contains(' · ')) {
    return '${names.length} partners join $into.';
  }
  return '${names.length} partners leave $from and join $into.';
}

/// The notice after a fellowship change. Inactive partners are named
/// separately: they move too, so the old group does not come back with them.
String fellowshipChangeNotice(String done, int moved, int inactiveMoved) {
  final parts = <String>[done];
  if (moved > 0) parts.add('$moved ${moved == 1 ? 'partner' : 'partners'} updated');
  if (inactiveMoved > 0) parts.add('$inactiveMoved inactive moved with them');
  return '${parts.join(' · ')}. Undo it below, under Recent changes.';
}
