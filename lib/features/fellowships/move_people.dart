import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/errors/plain_error.dart';
import '../../core/extensions/async_value_ext.dart';
import '../../core/notifications/sel_notice.dart';
import '../../core/utils/text_case_utils.dart';
import '../../design/seline.dart';
import '../auth/providers/auth_providers.dart';
import '../church/providers/church_settings_providers.dart';
import '../entries/providers/entries_providers.dart';
import '../operations/record_ops_repository.dart';
import '../partners/domain/partner.dart';
import '../partners/providers/partners_providers.dart';
import 'fellowship_match.dart';
import 'fellowship_providers.dart';

/// Moving people between fellowships, the same way from every door
/// (prototype "Moving people", approved 12 Nov 2026):
///
/// * the partner's Edit picks a fellowship from [pickFellowship];
/// * Tools · Move people and a fellowship's ⋯ · Move people tick people in
///   [MovePeopleChooser], then the same picker;
/// * rename, merge into and close live on the fellowship's ⋯ menu.
///
/// Every change runs on the server as a recorded operation, so it can be
/// undone straight after (the notice's Undo, or the summary's) and later
/// from Tools · Changes. Staff changes happen straight away; pastors are
/// told on their bell.

int _activeIn(List<Partner> partners, String name) =>
    partners.where((p) => p.isActive && fellowshipNamesMatch(p.fellowship, name)).length;

String _people(int n) => n == 1 ? '1 partner' : '$n partners';

/// Whoever is signed in, as the confirm and summary speak to them.
bool _isStaff(WidgetRef ref) => ref.read(userChurchIndexProvider).valueOrNull?.isStaff ?? false;

String _undoLine(WidgetRef ref) => _isStaff(ref)
    ? 'It happens straight away. Your pastor is told, and it can be undone from Tools · Changes.'
    : 'You can undo it straight after, or later from Tools · Changes.';


/// Puts a recorded change back, and says so. Works from the app's own
/// container, because the Undo it answers can outlive the page or panel
/// that made the change.
Future<void> undoFellowshipChange(ProviderContainer c, String opId) async {
  final idx = c.read(userChurchIndexProvider).valueOrNull;
  final notices = c.read(selNoticeControllerProvider.notifier);
  if (idx == null) return;
  try {
    await c.read(recordOpsRepositoryProvider).undo(churchId: idx.churchId, opId: opId);
    c.invalidate(partnersStreamProvider(false));
    c.invalidate(rankingEntriesProvider);
    notices.show('Put back as it was.', kind: SelNoticeKind.success);
  } catch (e) {
    notices.show(plainErrorText(plainError(e)), kind: SelNoticeKind.error);
  }
}

ProviderContainer _box(BuildContext context) => ProviderScope.containerOf(context, listen: false);

// ------------------------------------------------------------------ picker

/// Asks which fellowship. Existing ones come with how many are in them;
/// "New fellowship" takes a name and warns when it looks like one that
/// exists. [here] are where the people are now, shown but not choosable.
/// Returns the chosen name, or null.
Future<String?> pickFellowship(
  BuildContext context, {
  required String title,
  Set<String> here = const {},
  String? subtitle,
}) {
  return showSelSideSheet<String>(
    context,
    title: title,
    subtitle: subtitle,
    width: 420,
    child: _FellowshipPicker(here: here),
  );
}

/// The value [pickFellowshipFilter] returns for "All fellowships".
const allFellowships = '\u0000all';

/// Which fellowship to show: the same searchable list, with "All
/// fellowships" first and no New fellowship. Returns [allFellowships], a
/// name, or null when closed.
Future<String?> pickFellowshipFilter(BuildContext context, {String? current}) {
  return showSelSideSheet<String>(
    context,
    title: 'Show one fellowship',
    width: 420,
    child: _FellowshipPicker(here: const {}, filter: true, current: current),
  );
}

class _FellowshipPicker extends ConsumerStatefulWidget {
  const _FellowshipPicker({required this.here, this.filter = false, this.current});

  final Set<String> here;

  /// Choosing what to show, not where to move: All first, no New.
  final bool filter;
  final String? current;

  @override
  ConsumerState<_FellowshipPicker> createState() => _FellowshipPickerState();
}

class _FellowshipPickerState extends ConsumerState<_FellowshipPicker> {
  String _query = '';
  bool _adding = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = ref.watch(knownFellowshipsProvider);
    final partners = ref.watch(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[];
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final f in known)
        if (q.isEmpty || f.toLowerCase().contains(q)) f,
    ];
    final typed = TextCaseUtils.toTitleCase(_name.text.trim());
    final exact = known.where((k) => fellowshipNamesMatch(k, typed)).firstOrNull;
    final similar = typed.length < 3 || exact != null ? null : suggestSimilarFellowship(typed, known);

    Widget option(String f, {String? label, String? count}) {
      final isHere = widget.here.any((h) => fellowshipNamesMatch(h, f));
      final isCurrent = widget.filter &&
          (f == allFellowships ? widget.current == null : widget.current != null && fellowshipNamesMatch(widget.current!, f));
      return Padding(
        padding: const EdgeInsets.only(bottom: SelSpace.x2),
        child: Material(
          color: isCurrent ? Sel.skyTint : Sel.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isCurrent ? Sel.sky : Sel.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: isHere ? null : () => Navigator.of(context).pop(f),
            child: Opacity(
              opacity: isHere ? .5 : 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      f == allFellowships
                          ? const CircleAvatar(
                              radius: 16,
                              backgroundColor: Sel.skyWash,
                              child: Icon(LucideIcons.users, size: 15, color: Sel.ink),
                            )
                          : _Initials(label ?? f),
                      const SizedBox(width: SelSpace.x3),
                      Expanded(
                        child: Text(
                          label ?? f,
                          style: SelType.bodyMedium.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: SelSpace.x2),
                      Text(
                        count ?? (isHere ? 'where they are now' : _people(_activeIn(partners, f))),
                        style: SelType.small,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (known.length > 6) ...[
          SelField(
            hint: 'Find a fellowship',
            prefixIcon: LucideIcons.search,
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: SelSpace.x3),
        ],
        if (widget.filter && q.isEmpty)
          option(allFellowships, label: 'All fellowships', count: _people(partners.where((p) => p.isActive).length)),
        for (final f in shown) option(f),
        if (shown.isEmpty) Padding(
          padding: const EdgeInsets.symmetric(vertical: SelSpace.x3),
          child: Text('No fellowship matches “$_query”.', style: SelType.bodyMuted),
        ),
        const SizedBox(height: SelSpace.x2),
        if (widget.filter)
          const SizedBox.shrink()
        else if (!_adding)
          SelButton(
            label: 'New fellowship',
            icon: LucideIcons.plus,
            onPressed: () => setState(() {
              _adding = true;
              _name.text = _query.trim();
            }),
          )
        else ...[
          SelField(
            controller: _name,
            label: 'New fellowship name',
            hint: 'Ebenezer',
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          if (exact != null || similar != null) ...[
            const SizedBox(height: SelSpace.x3),
            _Warn(
              text: exact != null
                  ? '$exact already exists.'
                  : 'There is already $similar (${_people(_activeIn(partners, similar!))}). Did you mean it?',
              action: 'Use ${exact ?? similar}',
              onAction: () => Navigator.of(context).pop(exact ?? similar),
            ),
          ],
          const SizedBox(height: SelSpace.x3),
          Align(
            alignment: Alignment.centerRight,
            child: SelButton.cyan(
              label: typed.isEmpty ? 'Use this name' : 'Use “$typed”',
              onPressed: typed.isEmpty || exact != null ? null : () => Navigator.of(context).pop(typed),
            ),
          ),
        ],
      ],
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final text = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first[0].toUpperCase()
        : (parts.first[0] + parts.last[0]).toUpperCase();
    return CircleAvatar(
      radius: 16,
      backgroundColor: Sel.skyWash,
      child: Text(text, style: SelType.small.copyWith(color: Sel.ink, fontWeight: FontWeight.w800)),
    );
  }
}

class _Warn extends StatelessWidget {
  const _Warn({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    decoration: BoxDecoration(color: Sel.warningWash, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Expanded(child: Text(text, style: SelType.bodySm.copyWith(color: Sel.text))),
        if (action != null) SelLink(label: action!, onTap: onAction!),
      ],
    ),
  );
}

// ------------------------------------------------------------------ moving

/// Confirms, then moves [moving] into [to]. One person goes straight
/// through with an Undo notice; several get the progress window and a
/// summary with Undo. Returns true when the move went through.
Future<bool> confirmAndMove(
  BuildContext context,
  WidgetRef ref, {
  required List<Partner> moving,
  required String to,
}) async {
  final idx = ref.read(userChurchIndexProvider).valueOrNull;
  if (idx == null || moving.isEmpty) return false;
  final partners = ref.read(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[];
  final known = ref.read(knownFellowshipsProvider);
  final isNew = !known.any((k) => fellowshipNamesMatch(k, to));
  final now = _activeIn(partners, to);
  final names = moving.take(6).map((p) => '• ${p.fullName}, from ${p.fellowship.isEmpty ? 'no fellowship' : p.fellowship}');
  final more = moving.length > 6 ? '\n• and ${moving.length - 6} more' : '';
  final one = moving.length == 1;
  final ok = await selConfirm(
    context,
    title: one ? 'Move ${moving.first.fullName} to $to?' : 'Move ${moving.length} partners to $to?',
    message:
        '${isNew ? 'A new fellowship, $to, is made.' : '$to goes from ${_people(now)} to ${_people(now + moving.length)}.'}\n'
        '${names.join('\n')}$more\n\n'
        'Their giving moves with them, so each fellowship’s totals stay right. ${_undoLine(ref)}',
    confirmLabel: one ? 'Move' : 'Move ${moving.length}',
  );
  if (!ok || !context.mounted) return false;
  return applyMove(context, ref, moving: moving, to: to);
}

/// The move itself, without asking (the partner's Edit has already said
/// what saving does).
Future<bool> applyMove(
  BuildContext context,
  WidgetRef ref, {
  required List<Partner> moving,
  required String to,
}) async {
  final idx = ref.read(userChurchIndexProvider).valueOrNull;
  if (idx == null) return false;
  final box = _box(context);
  final staff = _isStaff(ref);
  final router = GoRouter.of(context);
  final repo = ref.read(recordOpsRepositoryProvider);
  void refresh() {
    box.invalidate(partnersStreamProvider(false));
    box.invalidate(rankingEntriesProvider);
  }
  Future<FellowshipChangeResult> call() => repo
      .fellowshipChange(churchId: idx.churchId, kind: 'move', partnerIds: [for (final p in moving) p.id], toName: to);

  if (moving.length == 1) {
    final p = moving.first;
    try {
      final r = await call();
      refresh();
      if (!context.mounted) return true;
      final opId = r.opId;
      selNotice(
        context,
        opId == null ? '${p.fullName} is already in $to.' : '${p.fullName} moved to $to.',
        kind: SelNoticeKind.success,
        duration: opId == null ? SelNoticeDuration.standard : SelNoticeDuration.undo,
        actionLabel: opId == null ? null : 'Undo',
        onAction: opId == null ? null : () => undoFellowshipChange(box, opId),
      );
      return true;
    } catch (e) {
      if (context.mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
      return false;
    }
  }

  String? opId;
  final inToBefore = _activeIn(ref.read(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[], to);
  final byFrom = <String, int>{};
  for (final p in moving) {
    final f = p.fellowship.isEmpty ? 'no fellowship' : p.fellowship;
    byFrom[f] = (byFrom[f] ?? 0) + 1;
  }
  final done = await runWithProgress(
    context,
    title: 'Moving ${moving.length} partners to $to',
    subtitle: 'Pillr does this on the server; keep this page open.',
    steps: [
      'Checking the ${moving.length} partners',
      'Moving them and their giving to $to',
      'Updating the fellowship totals',
    ],
    run: (w) async {
      final r = await runServerSteps(w, call);
      opId = r.opId;
      if (r.opId == null) {
        return SelSummary(title: 'Nothing to move', subtitle: 'They were all in $to already.');
      }
      return SelSummary(
        title: '${r.moved} ${r.moved == 1 ? 'partner' : 'partners'} moved to $to',
        numbers: [
          ('${r.moved}', 'moved'),
          ('${inToBefore + r.moved}', 'now in $to'),
        ],
        lines: [
          for (final e in byFrom.entries) SelSummaryLine('${e.value} from ${e.key}'),
          if (staff) const SelSummaryLine('Your pastor was told'),
        ],
        actions: [
          SelSummaryAction('Undo', () => undoFellowshipChange(box, r.opId!)),
          SelSummaryAction('See it in Changes', () => router.go('/tools?tool=changes'), link: true),
        ],
      );
    },
  );
  refresh();
  return done && opId != null;
}

// ------------------------------------------------------- the fellowship's ⋯

/// A rename, merge or dissolve on the server, with its progress and a
/// summary that can undo it.
Future<void> _runChange(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
  required String from,
  required String to,
  required String working,
  required String done,
  List<SelSummaryLine> lines = const [],
}) async {
  final idx = ref.read(userChurchIndexProvider).valueOrNull;
  if (idx == null) return;
  // The row that opened this can vanish when the change lands (a merged
  // fellowship leaves the list), so take everything needed now.
  final box = _box(context);
  final staff = _isStaff(ref);
  final router = GoRouter.of(context);
  final repo = ref.read(recordOpsRepositoryProvider);
  final partners = ref.read(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[];
  final expect = _activeIn(partners, from);
  await runWithProgress(
    context,
    title: working,
    subtitle: 'Pillr does this on the server; keep this page open.',
    steps: [
      'Checking the ${_people(expect)} in $from',
      kind == 'rename' ? 'Giving them the new name' : 'Moving them and their giving to $to',
      'Updating the fellowship totals',
    ],
    run: (w) async {
      final r = await runServerSteps(
        w,
        () => repo.fellowshipChange(
          churchId: idx.churchId,
          kind: kind,
          fromNames: [from],
          toName: to,
          expectActive: expect,
        ),
      );
      if (r.opId == null) return const SelSummary(title: 'Nothing to change');
      return SelSummary(
        title: done,
        numbers: [('${r.moved}', kind == 'rename' ? 'partners renamed' : 'moved')],
        lines: [
          ...lines,
          if (staff) const SelSummaryLine('Your pastor was told'),
        ],
        actions: [
          SelSummaryAction('Undo', () => undoFellowshipChange(box, r.opId!)),
          SelSummaryAction('See it in Changes', () => router.go('/tools?tool=changes'), link: true),
        ],
      );
    },
  );
  box.invalidate(partnersStreamProvider(false));
  box.invalidate(rankingEntriesProvider);
}

/// Rename: everyone stays, the name changes everywhere. A name that is
/// already taken is offered as a merge instead.
Future<void> renameFellowship(BuildContext context, WidgetRef ref, String from) async {
  final controller = TextEditingController(text: from);
  final known = ref.read(knownFellowshipsProvider);
  final partners = ref.read(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[];
  final n = _activeIn(partners, from);
  final result = await showSelSideSheet<String>(
    context,
    title: 'Rename $from',
    width: 420,
    child: StatefulBuilder(
      builder: (context, setLocal) {
        final to = TextCaseUtils.toTitleCase(controller.text.trim());
        final clash = known.where((k) => !fellowshipNamesMatch(k, from) && fellowshipNamesMatch(k, to)).firstOrNull;
        final same = to.isEmpty || to == from;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelField(controller: controller, label: 'New name', autofocus: true, onChanged: (_) => setLocal(() {})),
            const SizedBox(height: SelSpace.x3),
            if (clash != null)
              _Warn(
                text: '$clash already exists. To bring the two together, merge instead.',
                action: 'Merge into $clash',
                onAction: () => Navigator.of(context).pop('\u0000merge:$clash'),
              )
            else
              _Say('All ${_people(n)} stay; their fellowship reads “${same ? from : to}” everywhere, on reports and letters too.'),
            const SizedBox(height: SelSpace.x2),
            Text(_undoLine(ref), style: SelType.small),
            const SizedBox(height: SelSpace.x4),
            Align(
              alignment: Alignment.centerRight,
              child: SelButton.cyan(
                label: 'Rename',
                onPressed: same || clash != null ? null : () => Navigator.of(context).pop(to),
              ),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  if (result == null || !context.mounted) return;
  if (result.startsWith('\u0000merge:')) {
    await mergeFellowship(context, ref, from, into: result.substring(7));
    return;
  }
  await _runChange(context, ref,
      kind: 'rename', from: from, to: result, working: 'Renaming $from', done: '$from is now $result',
      lines: const [SelSummaryLine('Reports and letters use the new name')]);
}

/// Merge into: everyone in [from] joins another fellowship and [from]
/// closes. For two names that are the same group, like Shilo and Shiloh.
Future<void> mergeFellowship(BuildContext context, WidgetRef ref, String from, {String? into}) async {
  final to = into ??
      await pickFellowship(context, title: 'Merge $from into', here: {from},
          subtitle: 'Everyone in $from joins the one you pick, and $from closes.');
  if (to == null || !context.mounted) return;
  final partners = ref.read(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[];
  final n = _activeIn(partners, from), m = _activeIn(partners, to);
  final ok = await selConfirm(
    context,
    title: 'Merge $from into $to?',
    message: '${n == 1 ? 'The 1 partner in $from joins' : 'All $n partners in $from join'} $to, which then has ${_people(n + m)}. $from closes. '
        'Their giving moves with them. ${_undoLine(ref)}',
    confirmLabel: 'Merge',
  );
  if (!ok || !context.mounted) return;
  await _runChange(context, ref,
      kind: 'dissolve', from: from, to: to, working: 'Merging $from into $to', done: '$from is merged into $to',
      lines: [SelSummaryLine('$from is closed')]);
}

/// Close: only an empty fellowship. One with people in it offers to move
/// them first, or to merge them all in one step.
Future<void> closeFellowship(BuildContext context, WidgetRef ref, String name) async {
  final idx = ref.read(userChurchIndexProvider).valueOrNull;
  if (idx == null) return;
  final partners = ref.read(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[];
  final n = _activeIn(partners, name);
  if (n > 0) {
    final choice = await showSelSideSheet<String>(
      context,
      title: '$name still has ${_people(n)}',
      width: 420,
      child: Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Warn(text: 'A fellowship is closed only when it is empty, so nobody is left without one.'),
            const SizedBox(height: SelSpace.x4),
            SelButton.cyan(label: 'Move them first', onPressed: () => Navigator.of(context).pop('move')),
            const SizedBox(height: SelSpace.x2),
            SelButton(label: 'Merge all $n into another and close', onPressed: () => Navigator.of(context).pop('merge')),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'move') context.go('/fellowships/move?from=${Uri.encodeQueryComponent(name)}&all=1');
    if (choice == 'merge') await mergeFellowship(context, ref, name);
    return;
  }
  final ok = await selConfirm(
    context,
    title: 'Close $name?',
    message: '$name is empty. It leaves the lists; nothing is deleted.',
    confirmLabel: 'Close it',
  );
  if (!ok || !context.mounted) return;
  final catalog = ref.read(churchSettingsProvider).valueOrNull?.fellowshipNames ?? const <String>[];
  final repo = ref.read(churchSettingsRepositoryProvider);
  final box = _box(context);
  try {
    await repo.setFellowshipNames(idx.churchId, [for (final c in catalog) if (!fellowshipNamesMatch(c, name)) c]);
    if (!context.mounted) return;
    selNotice(
      context,
      '$name is closed.',
      kind: SelNoticeKind.success,
      duration: SelNoticeDuration.undo,
      actionLabel: 'Undo',
      onAction: () async {
        final now = box.read(churchSettingsProvider).valueOrNull?.fellowshipNames ?? const <String>[];
        await repo.setFellowshipNames(idx.churchId, [...now, name]);
      },
    );
  } catch (e) {
    if (context.mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
  }
}

/// A new, empty fellowship. Warns when the name looks like one that exists.
Future<void> createFellowship(BuildContext context, WidgetRef ref) async {
  final idx = ref.read(userChurchIndexProvider).valueOrNull;
  if (idx == null) return;
  final known = ref.read(knownFellowshipsProvider);
  final controller = TextEditingController();
  final name = await showSelSideSheet<String>(
    context,
    title: 'New fellowship',
    width: 420,
    child: StatefulBuilder(
      builder: (context, setLocal) {
        final typed = TextCaseUtils.toTitleCase(controller.text.trim());
        final exact = known.where((k) => fellowshipNamesMatch(k, typed)).firstOrNull;
        final similar = typed.length < 3 || exact != null ? null : suggestSimilarFellowship(typed, known);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelField(controller: controller, label: 'Name', hint: 'Ebenezer', autofocus: true, onChanged: (_) => setLocal(() {})),
            if (exact != null || similar != null) ...[
              const SizedBox(height: SelSpace.x3),
              _Warn(text: exact != null ? '$exact already exists.' : 'There is already $similar. Is this the same group?'),
            ],
            const SizedBox(height: SelSpace.x2),
            Text('It starts empty. Move people into it from Tools · Move people or a partner’s Edit.', style: SelType.small),
            const SizedBox(height: SelSpace.x4),
            Align(
              alignment: Alignment.centerRight,
              child: SelButton.cyan(
                label: 'Create',
                onPressed: typed.isEmpty || exact != null ? null : () => Navigator.of(context).pop(typed),
              ),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  if (name == null || !context.mounted) return;
  final catalog = ref.read(churchSettingsProvider).valueOrNull?.fellowshipNames ?? const <String>[];
  final partners = ref.read(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[];
  try {
    await ref.read(fellowshipOpsProvider).create(
      churchId: idx.churchId,
      name: name,
      catalog: catalog,
      partnerFellowships: partners.map((p) => p.fellowship),
    );
    if (context.mounted) selNotice(context, '$name is ready. Move people into it next.', kind: SelNoticeKind.success);
  } catch (e) {
    if (context.mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
  }
}

class _Say extends StatelessWidget {
  const _Say(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(14)),
    child: Text(text, style: SelType.bodySm.copyWith(color: Sel.ink)),
  );
}

// ------------------------------------------------------------- the chooser

/// Tick people, then Move to…. Everyone (Tools · Move people), or one
/// fellowship's people when [fellowship] is set (its ⋯ · Move people). The
/// "N chosen · Move to…" bar is pinned to the bottom, as on the Queue.
class MovePeopleScreen extends ConsumerStatefulWidget {
  const MovePeopleScreen({super.key, this.fellowship, this.tickAll = false});

  final String? fellowship;

  /// Start with everyone ticked (Close · Move them first).
  final bool tickAll;

  @override
  ConsumerState<MovePeopleScreen> createState() => _MovePeopleScreenState();
}

class _MovePeopleScreenState extends ConsumerState<MovePeopleScreen> {
  final _picked = <String>{};
  String _query = '';
  String? _filter;
  bool _seeded = false;
  bool _busy = false;
  static const _page = 150;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(partnersStreamProvider(false));
    final partners = [
      for (final p in async.valueOrNull ?? const <Partner>[])
        if (p.isActive) p,
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    final locked = widget.fellowship;
    final scope = locked ?? _filter;
    if (!_seeded && widget.tickAll && locked != null && partners.isNotEmpty) {
      _seeded = true;
      _picked.addAll(partners.where((p) => fellowshipNamesMatch(p.fellowship, locked)).map((p) => p.id));
    }
    final q = _query.trim().toLowerCase();
    final list = [
      for (final p in partners)
        if ((scope == null || fellowshipNamesMatch(p.fellowship, scope)) &&
            (q.isEmpty || p.fullName.toLowerCase().contains(q) || p.memberId.toLowerCase().contains(q)))
          p,
    ];
    final chosen = [for (final p in partners) if (_picked.contains(p.id)) p];
    final allOn = list.isNotEmpty && list.every((p) => _picked.contains(p.id));
    final from = chosen.map((p) => p.fellowship.isEmpty ? 'no fellowship' : p.fellowship).toSet();
    final names = chosen.take(2).map((p) => p.fullName).join(', ') +
        (chosen.length > 2 ? ' and ${chosen.length - 2} more' : '');

    return SelPageBody(
      bottomBar: chosen.isEmpty
          ? null
          : SelChoiceBar(
              count: chosen.length,
              note: '$names · from ${from.length == 1 ? from.first : '${from.length} fellowships'}',
              busy: _busy,
              action: 'Move to…',
              onClear: () => setState(_picked.clear),
              onAction: () => _move(chosen),
            ),
      children: [
        SelPageTitle(
          title: locked == null ? 'Move people' : 'Move people from $locked',
          subtitle: locked == null
              ? 'Tick the people, then choose where they go. Their giving moves with them.'
              : 'Tick who is moving. Everyone else stays in $locked.',
          actions: [
            SelButton(
              label: locked == null ? 'Back to Tools' : 'Cancel',
              icon: LucideIcons.arrowLeft,
              onPressed: () => context.go(locked == null ? '/tools' : '/fellowships'),
            ),
          ],
        ),
        // Search, and one control for which fellowship: a church can have
        // thirty, and a wall of pills buries the list (Hick).
        LayoutBuilder(
          builder: (context, c) {
            final search = SelField(
              hint: locked == null ? 'Find a partner by name or member ID' : 'Find someone in $locked',
              prefixIcon: LucideIcons.search,
              onChanged: (v) => setState(() {
                _query = v;
                _shown = _page;
              }),
            );
            if (locked != null) return search;
            final filter = _FilterButton(
              label: _filter == null ? 'All fellowships' : _filter!,
              count: _filter == null ? partners.length : _activeIn(partners, _filter!),
              active: _filter != null,
              onTap: () async {
                final v = await pickFellowshipFilter(context, current: _filter);
                if (v == null || !mounted) return;
                setState(() {
                  _filter = v == allFellowships ? null : v;
                  _shown = _page;
                });
              },
              onClear: () => setState(() => _filter = null),
            );
            if (c.maxWidth < 600) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [search, const SizedBox(height: SelSpace.x3), filter],
              );
            }
            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: SelSpace.x3),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: filter),
              ],
            );
          },
        ),
        const SizedBox(height: SelSpace.x4),
        if (async.isLoading && partners.isEmpty)
          const SelCard(child: SelSkeletonRows())
        else
          SelCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: Sel.rowHover,
                  padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          scope == null ? '${list.length} partners' : '${list.length} in $scope',
                          style: SelType.small.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (list.isNotEmpty)
                        SelLink(
                          label: allOn ? 'Untick all' : 'Tick all ${list.length}',
                          onTap: () => setState(() {
                            if (allOn) {
                              _picked.removeAll(list.map((p) => p.id));
                            } else {
                              _picked.addAll(list.map((p) => p.id));
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(SelSpace.x6),
                    child: Text(
                      q.isEmpty ? 'Nobody is in ${scope ?? 'the book'} now.' : 'Nobody matches “$_query”.',
                      style: SelType.bodyMuted,
                      textAlign: TextAlign.center,
                    ),
                  ),
                // A church of 500 builds 150 rows at a time, so a phone
                // stays quick; Tick all still ticks the whole list.
                for (final p in list.take(_shown))
                  _TickRow(
                    key: ValueKey(p.id),
                    partner: p,
                    on: _picked.contains(p.id),
                    onTap: () => setState(() => _picked.contains(p.id) ? _picked.remove(p.id) : _picked.add(p.id)),
                  ),
                if (list.length > _shown)
                  Padding(
                    padding: const EdgeInsets.all(SelSpace.x4),
                    child: Center(
                      child: SelButton(
                        label: 'Show ${(list.length - _shown).clamp(0, _page)} more of ${list.length - _shown}',
                        onPressed: () => setState(() => _shown += _page),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _move(List<Partner> chosen) async {
    final here = chosen.map((p) => p.fellowship).toSet();
    final to = await pickFellowship(
      context,
      title: chosen.length == 1 ? 'Move ${chosen.first.fullName} to' : 'Move ${chosen.length} partners to',
      here: here.length == 1 ? here : const {},
    );
    if (to == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await confirmAndMove(context, ref, moving: chosen, to: to);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _picked.clear();
    });
  }
}

/// "Fellowship: All fellowships · 531 ▾", or the one chosen with a clear.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Sel.skyTint : Sel.card,
      shape: StadiumBorder(side: BorderSide(color: active ? Sel.sky : Sel.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SelLayout.tapTarget),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.users, size: 16, color: Sel.warm),
                const SizedBox(width: SelSpace.x2),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: label, style: SelType.bodyMedium.copyWith(color: Sel.ink, fontWeight: FontWeight.w700)),
                        TextSpan(text: '  $count', style: SelType.small),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SelSpace.x1),
                if (active)
                  IconButton(
                    tooltip: 'Show all fellowships',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(LucideIcons.x, size: 16, color: Sel.ink),
                    onPressed: onClear,
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(LucideIcons.chevronDown, size: 16, color: Sel.ink),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TickRow extends StatelessWidget {
  const _TickRow({super.key, required this.partner, required this.on, required this.onTap});

  final Partner partner;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = partner;
    return Material(
      color: on ? Sel.skyTint : Sel.card,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Sel.rowLine))),
          child: Row(
            children: [
              Checkbox(value: on, onChanged: (_) => onTap()),
              const SizedBox(width: SelSpace.x1),
              _Initials(p.fullName),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SelType.body.copyWith(color: Sel.ink, fontWeight: FontWeight.w600)),
                    Text(
                      [p.fellowship.isEmpty ? 'No fellowship' : p.fellowship, if (p.memberId.isNotEmpty) p.memberId]
                          .join(' · '),
                      style: SelType.small,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
