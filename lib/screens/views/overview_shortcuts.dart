import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../design/seline.dart';
import '../../features/shortcuts/shortcuts.dart';

/// Up to four shortcuts at the top of Overview, each straight to a page.
/// Edit opens the picker in place, with every page that can be pinned.
class OverviewShortcuts extends ConsumerStatefulWidget {
  const OverviewShortcuts({super.key, required this.isPastor});

  final bool isPastor;

  @override
  ConsumerState<OverviewShortcuts> createState() => _OverviewShortcutsState();
}

class _OverviewShortcutsState extends ConsumerState<OverviewShortcuts> {
  List<String>? _draft;

  @override
  Widget build(BuildContext context) {
    final available = shortcutsFor(isPastor: widget.isPastor);
    final byId = {for (final s in available) s.id: s};
    final saved = ref.watch(shortcutsProvider).where(byId.containsKey).toList();
    final editing = _draft != null;
    final chosen = (_draft ?? saved).map((id) => byId[id]!).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelSectionLabel(
          label: 'Shortcuts',
          trailing: editing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelButton(
                      label: 'Cancel',
                      kind: SelButtonKind.quiet,
                      dense: true,
                      onPressed: () => setState(() => _draft = null),
                    ),
                    const SizedBox(width: SelSpace.x2),
                    SelButton.cyan(
                      label: 'Done',
                      icon: LucideIcons.check,
                      onPressed: () async {
                        await ref
                            .read(shortcutsProvider.notifier)
                            .save(_draft!);
                        if (mounted) setState(() => _draft = null);
                      },
                    ),
                  ],
                )
              : SelButton(
                  label: 'Edit',
                  icon: LucideIcons.pencil,
                  kind: SelButtonKind.quiet,
                  dense: true,
                  onPressed: () => setState(() => _draft = [...saved]),
                ),
        ),
        if (editing)
          Padding(
            padding: const EdgeInsets.only(bottom: SelSpace.x2),
            child: Text(
              '${chosen.length} of $maxShortcuts chosen. '
              'Use the arrows to reorder, or remove one to add another.',
              style: SelType.small,
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth < 640 ? 2 : 4;
            final w = (c.maxWidth - (cols - 1) * SelSpace.x3) / cols;
            return Wrap(
              spacing: SelSpace.x3,
              runSpacing: SelSpace.x3,
              children: [
                for (var i = 0; i < chosen.length; i++)
                  SizedBox(
                    width: w,
                    child: _Tile(
                      shortcut: chosen[i],
                      onTap: editing ? null : () => context.go(chosen[i].path),
                      onRemove: editing
                          ? () => setState(() => _draft!.removeAt(i))
                          : null,
                      onLeft: editing && i > 0
                          ? () => setState(() {
                              final id = _draft!.removeAt(i);
                              _draft!.insert(i - 1, id);
                            })
                          : null,
                    ),
                  ),
                if (editing)
                  for (var i = chosen.length; i < maxShortcuts; i++)
                    SizedBox(width: w, child: const _FreePlace()),
              ],
            );
          },
        ),
        if (editing) ...[
          const SizedBox(height: SelSpace.x4),
          SelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Add a shortcut', style: SelType.subtitleSm),
                const SizedBox(height: SelSpace.x1),
                Text(
                  'Pick anything you open often. Only you see your shortcuts.',
                  style: SelType.small,
                ),
                for (final group in {for (final s in available) s.group}) ...[
                  const SizedBox(height: SelSpace.x4),
                  Text(group, style: SelType.caption),
                  const SizedBox(height: SelSpace.x2),
                  Wrap(
                    spacing: SelSpace.x2,
                    runSpacing: SelSpace.x2,
                    children: [
                      for (final s in available.where((s) => s.group == group))
                        _Option(
                          shortcut: s,
                          picked: _draft!.contains(s.id),
                          full: _draft!.length >= maxShortcuts,
                          onTap: () => setState(() {
                            if (_draft!.contains(s.id)) {
                              _draft!.remove(s.id);
                            } else if (_draft!.length < maxShortcuts) {
                              _draft!.add(s.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: SelSpace.x4),
                Text(
                  'Up to $maxShortcuts. When all are full, remove one to add another.',
                  style: SelType.small,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.shortcut, this.onTap, this.onRemove, this.onLeft});

  final Shortcut shortcut;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onLeft;

  @override
  Widget build(BuildContext context) {
    final editing = onRemove != null;
    return SelCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x3,
        vertical: SelSpace.x3,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Sel.skyWash.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(SelRadius.card),
            ),
            child: Icon(shortcut.icon, size: 20, color: Sel.ink),
          ),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shortcut.label,
                  style: SelType.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  shortcut.hint,
                  style: SelType.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (editing) ...[
            if (onLeft != null)
              SelIconButton(
                icon: LucideIcons.arrowLeft,
                tooltip: 'Move ${shortcut.label} earlier',
                onPressed: onLeft,
              ),
            SelIconButton(
              icon: LucideIcons.x,
              tooltip: 'Remove ${shortcut.label}',
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

class _FreePlace extends StatelessWidget {
  const _FreePlace();

  @override
  Widget build(BuildContext context) => Container(
    height: 66,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(SelRadius.card),
      border: Border.all(color: Sel.borderMuted, width: 1.5),
    ),
    child: Text('Free place', style: SelType.small),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.shortcut,
    required this.picked,
    required this.full,
    required this.onTap,
  });

  final Shortcut shortcut;
  final bool picked;
  final bool full;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = picked || !full;
    return Semantics(
      button: true,
      selected: picked,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(SelRadius.card),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            width: 240,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x3,
              vertical: SelSpace.x2,
            ),
            decoration: BoxDecoration(
              color: picked ? Sel.skyWash.withValues(alpha: 0.4) : Sel.card,
              borderRadius: BorderRadius.circular(SelRadius.card),
              border: Border.all(color: picked ? Sel.cyanEdge : Sel.border),
            ),
            child: Row(
              children: [
                Icon(shortcut.icon, size: 18, color: Sel.ink),
                const SizedBox(width: SelSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shortcut.label, style: SelType.bodyMedium),
                      Text(
                        picked ? 'On your Overview' : shortcut.hint,
                        style: SelType.small,
                      ),
                    ],
                  ),
                ),
                Icon(
                  picked ? LucideIcons.check : LucideIcons.plus,
                  size: 18,
                  color: picked ? Sel.ink : Sel.cyanEdge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
