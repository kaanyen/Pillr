import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../features/leaderboard/giving_view.dart';
import '../core/notifications/sel_notice.dart';
import '../features/arms/domain/arm_tree.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/periods/domain/partnership_period.dart';
import '../features/periods/providers/periods_providers.dart';

/// Configuration — Partnership arms and Periods, merged.
///
/// Both are set-up-once structures that a church touches at the start of a
/// season and then leaves alone, and neither was ever used without the other:
/// a goal needs an arm *and* a period to mean anything. One screen, two
/// sections, on the same page.
class ConfigurationScreen extends ConsumerWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final arms = ref.watch(armsStreamProvider);
    final periods = ref.watch(periodsStreamProvider);
    final canEdit = (idx?.isPastor ?? false) || (idx?.isAdmin ?? false);

    final settings = ref.watch(churchSettingsProvider).valueOrNull;

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(armsStreamProvider);
        ref.invalidate(periodsStreamProvider);
      },
      children: [
        SelPageTitle(
          title: 'Configuration',
          subtitle:
              'What partners give toward, the years you measure, and the money you accept',
          actions: [
            if (canEdit) ...[
              SelButton(
                label: 'New period',
                onPressed: () =>
                    _periodDialog(context, ref, idx!.churchId, idx.uid),
              ),
              const SizedBox(width: SelSpace.x2),
              SelButton.cyan(
                label: 'Add an arm',
                icon: LucideIcons.plus,
                onPressed: () =>
                    _armDialog(context, ref, idx!.churchId, idx.uid),
              ),
            ],
          ],
        ),

        SelCard(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Periods', style: SelType.subtitle)),
                  Text(
                    'Exactly one is active. New giving counts toward it.',
                    style: SelType.small,
                  ),
                ],
              ),
              const SizedBox(height: SelSpace.x4),
              periods.when(
                loading: () => const SelSkeletonRows(count: 2),
                error: (e, _) => SelError(message: '$e'),
                data: (list) => list.isEmpty
                    ? const SelEmpty(
                        title: 'No periods yet',
                        message:
                            'Create a period to start measuring partnership.',
                        icon: LucideIcons.calendar,
                      )
                    : Wrap(
                        spacing: SelSpace.x3,
                        runSpacing: SelSpace.x3,
                        children: [
                          for (final p in [...list]
                            ..sort((a, b) => a.startDate.compareTo(b.startDate)))
                            SizedBox(
                              width: p.isActive ? 430 : 300,
                              child: _PeriodRow(
                                period: p,
                                canEdit: canEdit,
                                churchId: idx!.churchId,
                                money: money,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),

        const SizedBox(height: SelSpace.x4),

        SelPanel(
          title: 'Partnership arms',
          subtitle: canEdit
              ? 'What partners can give toward. Drag an arm onto another to make '
                    'it a sub-arm; its giving then counts toward that main arm.'
              : 'What partners can give toward.',
          contentPadding: EdgeInsets.zero,
          child: arms.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(SelSpace.cardPad),
              child: SelSkeletonRows(count: 3),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(SelSpace.cardPad),
              child: SelError(message: '$e'),
            ),
            data: (list) => list.isEmpty
                ? const SelEmpty(
                    title: 'No arms yet',
                    message: 'Add the causes your church partners toward.',
                    icon: LucideIcons.heartHandshake,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SelSpace.cardPad + 30,
                          SelSpace.x2,
                          SelSpace.cardPad,
                          SelSpace.x2,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text('Arm', style: SelType.caption)),
                            SizedBox(
                              width: 150,
                              child: Text(
                                'Entries this period',
                                style: SelType.caption,
                                textAlign: TextAlign.right,
                              ),
                            ),
                            SizedBox(
                              width: 190,
                              child: Text(
                                'Approved this period',
                                style: SelType.caption,
                                textAlign: TextAlign.right,
                              ),
                            ),
                            SizedBox(width: canEdit ? 260 : 0),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Sel.border),
                      _ArmsEditor(
                        arms: list,
                        canEdit: canEdit,
                        churchId: idx!.churchId,
                        uid: idx.uid,
                      ),
                      const Divider(height: 1, color: Sel.rowLine),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SelSpace.cardPad,
                          SelSpace.x3,
                          SelSpace.cardPad,
                          SelSpace.x4,
                        ),
                        child: Text(
                          "An arm that's turned off keeps its old entries; it "
                          'just stops appearing in new ones.',
                          style: SelType.small,
                        ),
                      ),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: SelSpace.x4),

        SelCard(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
          child: Wrap(
            spacing: SelSpace.x8,
            runSpacing: SelSpace.x3,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Money', style: SelType.subtitle),
                  Text(
                    'Totals are always in the church currency. Giving in '
                    "another currency is converted at the month's rate.",
                    style: SelType.small,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Church currency', style: SelType.small),
                      Text(
                        '${settings?.currency ?? 'GHS'} ${settings?.currencySymbol ?? ''}'
                            .trim(),
                        style: SelType.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(width: SelSpace.x6),
                  SelButton(
                    label: 'Update rates',
                    dense: true,
                    onPressed: () => context.go('/settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The arms list, grouped into main arms and sub-arms, with drag and drop.
///
/// Dropping an arm onto another makes it a sub-arm of that arm (or, dropped
/// on a sub-arm, of the same main arm). The zone under the list makes it a
/// main arm again. Each row's Move button does the same without dragging, for
/// touch screens and keyboards. A move only changes where arms sit: no entry,
/// total or goal is written, and the last move can be undone.
class _ArmsEditor extends ConsumerStatefulWidget {
  const _ArmsEditor({
    required this.arms,
    required this.canEdit,
    required this.churchId,
    required this.uid,
  });

  final List<PartnershipArm> arms;
  final bool canEdit;
  final String churchId;
  final String uid;

  @override
  ConsumerState<_ArmsEditor> createState() => _ArmsEditorState();
}

class _ArmsEditorState extends ConsumerState<_ArmsEditor> {
  String? _dragging;
  bool _saving = false;
  ({String message, List<ArmPlacement> undo})? _last;

  ArmTree get _tree => ArmTree(widget.arms);

  /// Where a drop on [target] would put the arm: under the target if it is a
  /// main arm, under its main arm if it is a sub-arm.
  String _parentFor(PartnershipArm target) =>
      _tree.mainOf(target.id)?.id ?? target.id;

  String? _whyNot(String armId, String? parentId) {
    if (parentId == null) return null;
    return _tree.whyCannotMoveUnder(armId, parentId);
  }

  Future<void> _move(String armId, String? parentId) async {
    final tree = _tree;
    final arm = tree.byId(armId);
    if (arm == null || _saving) return;
    final why = _whyNot(armId, parentId);
    if (why != null) {
      selNotice(context, why, kind: SelNoticeKind.error);
      return;
    }
    final placements = tree.placementsForMove(armId, parentId);
    if (placements.isEmpty) return;
    final undo = tree.undoOf(placements);
    final message = parentId == null
        ? '${arm.name} is a main arm.'
        : '${arm.name} now counts toward ${tree.byId(parentId)?.name}.';
    setState(() => _saving = true);
    try {
      await ref.read(armsRepositoryProvider).arrangeArms(
            churchId: widget.churchId,
            placements: placements,
          );
      if (mounted) setState(() => _last = (message: message, undo: undo));
    } catch (e) {
      if (mounted) selNotice(context, 'Couldn\'t move ${arm.name}: $e', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _undo() async {
    final last = _last;
    if (last == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(armsRepositoryProvider).arrangeArms(
            churchId: widget.churchId,
            placements: last.undo,
          );
      if (mounted) setState(() => _last = null);
    } catch (e) {
      if (mounted) selNotice(context, 'Couldn\'t undo: $e', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _moveDialog(PartnershipArm arm) async {
    final tree = _tree;
    final options = <(String?, String)>[
      (null, 'On its own, as a main arm'),
      for (final m in tree.mains)
        if (m.id != arm.id) (m.id, 'Under ${m.name}'),
    ];
    var choice = arm.parentArmId;
    final picked = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SelDialog(
          title: 'Move ${arm.name}',
          width: 440,
          scrollable: false,
          actions: [
            SelButton(
              label: 'Cancel',
              kind: SelButtonKind.quiet,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            SelButton.cyan(
              label: 'Move',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelSelect<String?>(
                value: choice,
                label: 'Where it counts',
                onChanged: (v) => setState(() => choice = v),
                items: [
                  for (final o in options)
                    DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                ],
              ),
              const SizedBox(height: SelSpace.x3),
              Text(
                'Its own entries stay as they are. A sub-arm\'s giving is added '
                'to its main arm\'s figures wherever they are shown.',
                style: SelType.small,
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == true) await _move(arm.id, choice);
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final rows = tree.flattened;
    final dragging = _dragging;

    Widget rowFor(({PartnershipArm arm, bool isSub}) r) {
      final arm = r.arm;
      final row = _ArmRow(
        arm: arm,
        isSub: r.isSub,
        subNames: [for (final c in tree.childrenOf(arm.id)) c.name],
        canEdit: widget.canEdit,
        churchId: widget.churchId,
        uid: widget.uid,
        onMove: widget.canEdit ? () => _moveDialog(arm) : null,
        dragHandle: !widget.canEdit
            ? null
            : Draggable<String>(
                data: arm.id,
                onDragStarted: () => setState(() => _dragging = arm.id),
                onDragEnd: (_) => setState(() => _dragging = null),
                onDraggableCanceled: (_, _) => setState(() => _dragging = null),
                feedback: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SelSpace.x4,
                      vertical: SelSpace.x2,
                    ),
                    decoration: BoxDecoration(
                      color: Sel.card,
                      borderRadius: BorderRadius.circular(SelRadius.pill),
                      border: Border.all(color: Sel.cyanEdge),
                    ),
                    child: Text(arm.name, style: SelType.bodyMedium),
                  ),
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Tooltip(
                    message: 'Drag onto another arm',
                    child: Padding(
                      padding: const EdgeInsets.all(SelSpace.x2),
                      child: Icon(LucideIcons.gripVertical, size: 18, color: Sel.ash),
                    ),
                  ),
                ),
              ),
      );
      if (!widget.canEdit) return row;
      return DragTarget<String>(
        onWillAcceptWithDetails: (d) =>
            d.data != arm.id && _whyNot(d.data, _parentFor(arm)) == null,
        onAcceptWithDetails: (d) => _move(d.data, _parentFor(arm)),
        builder: (context, candidates, rejected) {
          final hint = candidates.isNotEmpty
              ? 'Count toward ${tree.byId(_parentFor(arm))?.name}'
              : rejected.isNotEmpty && rejected.first != arm.id
                  ? _whyNot(rejected.first!, _parentFor(arm))
                  : null;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            color: candidates.isNotEmpty ? Sel.infoWash : Colors.transparent,
            child: Stack(
              children: [
                row,
                if (hint != null)
                  Positioned(
                    right: SelSpace.cardPad,
                    bottom: SelSpace.x1,
                    child: Text(hint, style: SelType.small),
                  ),
              ],
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Sel.border),
          rowFor(rows[i]),
        ],
        if (widget.canEdit && dragging != null)
          DragTarget<String>(
            onWillAcceptWithDetails: (d) => tree.byId(d.data)?.parentArmId != null,
            onAcceptWithDetails: (d) => _move(d.data, null),
            builder: (context, candidates, _) => Container(
              margin: const EdgeInsets.all(SelSpace.x3),
              padding: const EdgeInsets.all(SelSpace.x4),
              decoration: BoxDecoration(
                color: candidates.isNotEmpty ? Sel.infoWash : Sel.canvas,
                borderRadius: BorderRadius.circular(SelRadius.card),
                border: Border.all(color: Sel.borderMuted),
              ),
              alignment: Alignment.center,
              child: Text(
                tree.byId(dragging)?.parentArmId == null
                    ? 'Drop on another arm to make it a sub-arm'
                    : 'Drop here to make ${tree.byId(dragging)?.name} a main arm',
                style: SelType.bodyMuted,
              ),
            ),
          ),
        if (_last != null)
          Container(
            margin: const EdgeInsets.all(SelSpace.x3),
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x4,
              vertical: SelSpace.x2,
            ),
            decoration: BoxDecoration(
              color: Sel.infoWash,
              borderRadius: BorderRadius.circular(SelRadius.card),
            ),
            child: Row(
              children: [
                Expanded(child: Text(_last!.message, style: SelType.body)),
                SelButton(
                  label: 'Undo',
                  kind: SelButtonKind.quiet,
                  dense: true,
                  onPressed: _saving ? null : _undo,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ArmRow extends ConsumerWidget {
  const _ArmRow({
    required this.arm,
    required this.isSub,
    required this.subNames,
    required this.canEdit,
    required this.churchId,
    required this.uid,
    this.onMove,
    this.dragHandle,
  });

  final PartnershipArm arm;
  final bool isSub;
  final List<String> subNames;
  final bool canEdit;
  final String churchId;
  final String uid;
  final VoidCallback? onMove;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(givingViewProvider);
    final money = ref.watch(churchMoneyFormatProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: dragHandle == null ? SelSpace.cardPad : SelSpace.x2,
        right: SelSpace.cardPad,
        top: SelSpace.x3,
        bottom: SelSpace.x3,
      ),
      child: Row(
        children: [
          ?dragHandle,
          if (isSub) ...[
            const SizedBox(width: SelSpace.x6),
            Icon(LucideIcons.cornerDownRight, size: 16, color: Sel.ash),
            const SizedBox(width: SelSpace.x2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        arm.name,
                        style: SelType.bodyMedium.copyWith(
                          fontSize: 16,
                          color: arm.isActive ? Sel.ink : Sel.warm,
                        ),
                      ),
                    ),
                    if (!arm.isActive) ...[
                      const SizedBox(width: SelSpace.x2),
                      const SelStatusMark(status: SelStatus.inactive, label: 'Off'),
                    ],
                  ],
                ),
                if (subNames.isNotEmpty)
                  Text('Main arm · includes ${subNames.join(', ')}', style: SelType.small)
                else if (arm.description != null && arm.description!.isNotEmpty)
                  Text(arm.description!, style: SelType.small),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              isSub ? '' : '${view.armEntries[arm.id] ?? 0}',
              textAlign: TextAlign.right,
              style: SelType.body.copyWith(color: Sel.text),
            ),
          ),
          SizedBox(
            width: 190,
            child: Text(
              isSub ? '' : money(view.armTotal(arm.id)),
              textAlign: TextAlign.right,
              style: SelType.bodyMedium.copyWith(
                color: arm.isActive ? Sel.ink : Sel.warm,
              ),
            ),
          ),
          if (canEdit) ...[
            const SizedBox(width: SelSpace.x4),
            SelButton(
              label: 'Edit',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: () => _armDialog(context, ref, churchId, uid, existing: arm),
            ),
            SelButton(
              label: 'Move',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: onMove,
            ),
            SelButton(
              label: arm.isActive ? 'Turn off' : 'Turn on',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: () => ref.read(armsRepositoryProvider).setActive(
                    churchId: churchId,
                    armId: arm.id,
                    isActive: !arm.isActive,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodRow extends ConsumerWidget {
  const _PeriodRow({
    required this.period,
    required this.canEdit,
    required this.churchId,
    required this.money,
  });

  final PartnershipPeriod period;
  final bool canEdit;
  final String churchId;
  final String Function(num) money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final future = period.startDate.isAfter(now) && !period.isActive;
    final range =
        '${formatFirestoreDate(period.startDate, pattern: 'd MMM y')} to '
        '${formatFirestoreDate(period.endDate, pattern: 'd MMM y')}';
    final span = period.endDate.difference(period.startDate).inDays.clamp(1, 99999);
    final done = (now.difference(period.startDate).inDays / span).clamp(0.0, 1.0);
    final daysLeft = period.endDate.difference(now).inDays.clamp(0, 99999);
    final (tag, tagBg, tagFg) = period.isActive
        ? ('Active', Sel.ink, Sel.card)
        : future
        ? ('Ready to start', Sel.skyWash, Sel.ink)
        : ('Closed', Sel.track, Sel.text);

    Future<void> activate() async {
      final ok = await selConfirm(
        context,
        title: 'Activate ${period.name}?',
        message:
            'The current active period will be closed. New entries will be '
            'recorded against this one.',
        confirmLabel: 'Activate',
      );
      if (!ok) return;
      await ref.read(periodsRepositoryProvider).activatePeriod(
            churchId: churchId,
            periodId: period.id,
          );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: period.isActive ? Sel.skyTint : Sel.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: period.isActive ? Sel.ink : Sel.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tagBg,
              borderRadius: BorderRadius.circular(SelRadius.pill),
            ),
            child: Text(tag, style: SelType.tag.copyWith(color: tagFg)),
          ),
          const SizedBox(height: SelSpace.x3),
          Text(period.name, style: SelType.subtitleSm),
          Text(
            period.isActive ? '$range · $daysLeft days left' : range,
            style: SelType.small,
          ),
          const SizedBox(height: SelSpace.x2),
          if (period.isActive) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: done,
                minHeight: 8,
                backgroundColor: Sel.card,
                valueColor: const AlwaysStoppedAnimation(Sel.sky),
              ),
            ),
            const SizedBox(height: SelSpace.x2),
            Text(
              // The same sum the arms table and Overview add up.
              '${money(ref.watch(givingViewProvider).total)} approved so far',
              style: SelType.bodyMedium,
            ),
          ] else if (future && canEdit)
            InkWell(
              onTap: activate,
              child: Text(
                'Make it active',
                style: SelType.bodyMedium.copyWith(color: Sel.cyanEdge),
              ),
            )
          else ...[
            Text(
              '${money(period.totalApprovedAmount)} approved',
              style: SelType.bodyMedium,
            ),
            if (canEdit)
              InkWell(
                onTap: activate,
                child: Text(
                  'Make active again',
                  style: SelType.small.copyWith(
                    color: Sel.cyanEdge,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

Future<void> _armDialog(
  BuildContext context,
  WidgetRef ref,
  String churchId,
  String uid, {
  PartnershipArm? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final desc = TextEditingController(text: existing?.description ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => SelDialog(
      title: existing == null ? 'New partnership arm' : 'Edit arm',
      width: 460,
      scrollable: false,
      actions: [
        SelButton(
          label: 'Cancel',
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        SelButton.cyan(
          label: existing == null ? 'Create' : 'Save',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelField(controller: name, label: 'Name', hint: 'Missions', autofocus: true),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: desc,
            label: 'Description',
            hint: 'Optional — what this arm supports',
            maxLines: 2,
          ),
        ],
      ),
    ),
  );

  if (saved != true || name.text.trim().isEmpty) return;
  final repo = ref.read(armsRepositoryProvider);
  if (existing == null) {
    await repo.createArm(
      churchId: churchId,
      uid: uid,
      name: name.text,
      description: desc.text,
    );
  } else {
    await repo.updateArm(
      churchId: churchId,
      arm: existing,
      name: name.text,
      description: desc.text,
      isActive: existing.isActive,
      colorHex: existing.colorHex,
    );
  }
}

Future<void> _periodDialog(
  BuildContext context,
  WidgetRef ref,
  String churchId,
  String uid,
) async {
  final name = TextEditingController();
  var start = DateTime.now();
  var end = DateTime.now().add(const Duration(days: 90));

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SelDialog(
        title: 'New period',
        width: 460,
        scrollable: false,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SelButton.cyan(
            label: 'Create',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelField(
              controller: name,
              label: 'Name',
              hint: 'Q1 2027 Partnership',
              autofocus: true,
            ),
            const SizedBox(height: SelSpace.x4),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Starts',
                    value: start,
                    onPick: (d) => setState(() => start = d),
                  ),
                ),
                const SizedBox(width: SelSpace.x3),
                Expanded(
                  child: _DateField(
                    label: 'Ends',
                    value: end,
                    onPick: (d) => setState(() => end = d),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (saved != true || name.text.trim().isEmpty) return;
  await ref.read(periodsRepositoryProvider).createPeriod(
        churchId: churchId,
        uid: uid,
        name: name.text,
        startDate: start,
        endDate: end,
      );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return SelField(
      label: label,
      readOnly: true,
      controller: TextEditingController(
        text: formatFirestoreDate(value, pattern: 'd MMM y'),
      ),
      suffixIcon: const Icon(LucideIcons.calendar, size: 14, color: Sel.ash),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}
