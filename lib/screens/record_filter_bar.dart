import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../design/seline.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/record_filters.dart';

/// The filter row above Records and the ranked partners view.
///
/// Two slots, no more. Each active filter is a chip you can retarget or
/// remove; the button offers whatever is left. Options come from the entries
/// on hand, so there are never fellowships or people in the menu that would
/// return nothing.
class RecordFilterBar extends ConsumerWidget {
  const RecordFilterBar({super.key, required this.entries, required this.arms});

  /// Unfiltered entries — the pool the options are drawn from.
  final List<PartnershipEntry> entries;
  final List<PartnershipArm> arms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(recordFiltersProvider);
    final notifier = ref.read(recordFiltersProvider.notifier);
    final available = [
      for (final k in RecordFilterKind.values)
        if (!filters.isOn(k)) k,
    ];

    return Wrap(
      spacing: SelSpace.x2,
      runSpacing: SelSpace.x2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final kind in filters.active)
          _FilterChip(
            label: _kindLabel(kind),
            value: _valueLabel(context, ref, kind, filters),
            onTap: () => _pickValue(context, ref, kind),
            onRemove: () => notifier.remove(kind),
          ),
        if (available.isNotEmpty && !filters.isFull)
          _AddButton(
            kinds: available,
            onPick: (kind) => _pickValue(context, ref, kind),
          )
        else if (filters.isFull)
          Text(
            'Two filters at a time — remove one to add another.',
            style: SelType.small,
          ),
        if (!filters.isEmpty)
          SelButton(
            label: 'Clear',
            kind: SelButtonKind.quiet,
            onPressed: notifier.clear,
          ),
      ],
    );
  }

  String _kindLabel(RecordFilterKind kind) => switch (kind) {
    RecordFilterKind.dateRange => 'When',
    RecordFilterKind.fellowship => 'Fellowship',
    RecordFilterKind.arm => 'Arm',
    RecordFilterKind.amount => 'Amount',
    RecordFilterKind.recordedBy => 'Recorded by',
  };

  String _valueLabel(
    BuildContext context,
    WidgetRef ref,
    RecordFilterKind kind,
    RecordFilters f,
  ) => switch (kind) {
    RecordFilterKind.dateRange => f.dateRange?.label ?? '',
    RecordFilterKind.fellowship => f.fellowship ?? '',
    RecordFilterKind.arm =>
      arms.where((a) => a.id == f.armId).map((a) => a.name).firstOrNull ??
          'Arm',
    RecordFilterKind.amount => f.amount?.label ?? '',
    RecordFilterKind.recordedBy => _peopleById()[f.recordedBy] ?? 'Someone',
  };

  /// Distinct fellowships present in the data, in alphabetical order.
  List<String> _fellowships() {
    final seen = <String>{};
    for (final e in entries) {
      final v = e.partnerSnapshot['fellowship']?.toString().trim() ?? '';
      if (v.isNotEmpty) seen.add(v);
    }
    return seen.toList()..sort();
  }

  Map<String, String> _peopleById() {
    final out = <String, String>{};
    for (final e in entries) {
      final name = e.createdBySnapshot['fullName']?.toString().trim() ?? '';
      if (name.isNotEmpty) out[e.createdBy] = name;
    }
    return out;
  }

  Future<void> _pickValue(
    BuildContext context,
    WidgetRef ref,
    RecordFilterKind kind,
  ) async {
    final notifier = ref.read(recordFiltersProvider.notifier);
    final filters = ref.read(recordFiltersProvider);

    switch (kind) {
      case RecordFilterKind.dateRange:
        final v = await _menu<RecordDateRange>(context, [
          for (final r in RecordDateRange.values) (r, r.label),
        ]);
        if (v != null) notifier.set(filters.withDateRange(v));
      case RecordFilterKind.fellowship:
        final v = await _menu<String>(context, [
          for (final f in _fellowships()) (f, f),
        ]);
        if (v != null) notifier.set(filters.withFellowship(v));
      case RecordFilterKind.arm:
        final v = await _menu<String>(context, [
          for (final a in arms) (a.id, a.name),
        ]);
        if (v != null) notifier.set(filters.withArm(v));
      case RecordFilterKind.amount:
        final v = await _menu<RecordAmountBand>(context, [
          for (final b in RecordAmountBand.values) (b, b.label),
        ]);
        if (v != null) notifier.set(filters.withAmount(v));
      case RecordFilterKind.recordedBy:
        final people = _peopleById().entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final v = await _menu<String>(context, [
          for (final p in people) (p.key, p.value),
        ]);
        if (v != null) notifier.set(filters.withRecordedBy(v));
    }
  }
}

Future<T?> _menu<T>(BuildContext context, List<(T, String)> options) {
  if (options.isEmpty) return Future<T?>.value();
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final topLeft = box == null
      ? Offset.zero
      : box.localToGlobal(Offset.zero, ancestor: overlay);
  return showMenu<T>(
    context: context,
    color: Sel.card,
    position: RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + (box?.size.height ?? 0) + 4,
      overlay.size.width - topLeft.dx - 200,
      0,
    ),
    items: [
      for (final (value, label) in options)
        PopupMenuItem<T>(
          value: value,
          height: 36,
          child: Text(label, style: SelType.small.copyWith(color: Sel.ink)),
        ),
    ],
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onRemove,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Sel.card,
        border: Border.all(color: Sel.border),
        borderRadius: BorderRadius.circular(SelRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(SelRadius.pill),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SelSpace.x3,
                SelSpace.x2,
                SelSpace.x2,
                SelSpace.x2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$label ', style: SelType.small),
                  Text(value, style: SelType.small.copyWith(color: Sel.ink)),
                  const SizedBox(width: SelSpace.x1),
                  const Icon(LucideIcons.chevronDown, size: 11, color: Sel.ash),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(SelRadius.pill),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(
                SelSpace.x1,
                SelSpace.x2,
                SelSpace.x3,
                SelSpace.x2,
              ),
              child: Icon(LucideIcons.x, size: 12, color: Sel.ash),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.kinds, required this.onPick});

  final List<RecordFilterKind> kinds;
  final void Function(RecordFilterKind) onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<RecordFilterKind>(
      color: Sel.card,
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final k in kinds)
          PopupMenuItem<RecordFilterKind>(
            value: k,
            height: 36,
            child: Text(switch (k) {
              RecordFilterKind.dateRange => 'When',
              RecordFilterKind.fellowship => 'Fellowship',
              RecordFilterKind.arm => 'Arm',
              RecordFilterKind.amount => 'Amount',
              RecordFilterKind.recordedBy => 'Recorded by',
            }, style: SelType.small.copyWith(color: Sel.ink)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SelSpace.x3,
          vertical: SelSpace.x2,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Sel.border),
          borderRadius: BorderRadius.circular(SelRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.plus, size: 12, color: Sel.ash),
            const SizedBox(width: SelSpace.x2),
            Text('Add filter', style: SelType.small.copyWith(color: Sel.ink)),
          ],
        ),
      ),
    );
  }
}
