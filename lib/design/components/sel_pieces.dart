import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';
import 'sel_card.dart';
import 'sel_button.dart';

/// The pieces the canvas repeats across pages: a person's initials, a pill
/// tag, a breadcrumb, the navy "needs you" card, the list card and its rows,
/// tabs with counts, and tabs on a light track.

/// Up to two initials from a name: "Ama Boateng" → "AB".
String selInitials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

/// A person's initials in a light-sky circle, the way every list shows one.
class SelFace extends StatelessWidget {
  const SelFace(this.name, {super.key, this.size = 32});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: Sel.skyWash, shape: BoxShape.circle),
    child: Text(
      selInitials(name),
      style: SelType.small.copyWith(
        color: Sel.ink,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.36,
      ),
    ),
  );
}

enum SelTagTone {
  /// Grey: settled, nothing to do.
  plain,

  /// Light sky: waiting, or worth a look.
  waiting,

  /// Navy: the strongest state, such as Every month.
  strong,

  /// Faint sky: a gentle note.
  soft,
}

/// A small pill of text: a state, a count, a note.
class SelTag extends StatelessWidget {
  const SelTag(this.text, {super.key, this.tone = SelTagTone.plain});

  final String text;
  final SelTagTone tone;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (tone) {
      SelTagTone.plain => (Sel.track, Sel.text),
      SelTagTone.waiting => (Sel.skyWash, Sel.ink),
      SelTagTone.strong => (Sel.ink, Sel.card),
      SelTagTone.soft => (Sel.skyTint, Sel.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(SelRadius.pill),
      ),
      child: Text(text, style: SelType.small.copyWith(color: ink)),
    );
  }
}

/// Where this page sits: "Partners / Abena Darko". Every part but the last
/// is a link.
class SelBreadcrumb extends StatelessWidget {
  const SelBreadcrumb(this.parts, {super.key});

  /// Label and where it goes; the last part is the page itself.
  final List<(String, VoidCallback?)> parts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Text('  /  ', style: SelType.bodySm),
          if (i < parts.length - 1 && parts[i].$2 != null)
            SelLink(label: parts[i].$1, onTap: parts[i].$2)
          else
            Text(parts[i].$1, style: SelType.bodySm),
        ],
      ],
    );
  }
}

/// The navy card that says what needs this person: a label, a big headline,
/// a line under it, whatever rows explain it, one white button, and an
/// optional link at the foot.
class SelNavyCard extends StatelessWidget {
  const SelNavyCard({
    super.key,
    required this.label,
    required this.headline,
    required this.sub,
    this.body = const [],
    this.action,
    this.onAction,
    this.footLink,
    this.onFootLink,
  });

  final String label;
  final String headline;
  final String sub;
  final List<Widget> body;
  final String? action;
  final VoidCallback? onAction;
  final String? footLink;
  final VoidCallback? onFootLink;

  /// The light blue used for secondary text on navy.
  static const soft = Color(0xFFC9DEF3);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
      decoration: BoxDecoration(
        color: Sel.ink,
        borderRadius: BorderRadius.circular(SelRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: SelType.body.copyWith(color: soft)),
          const SizedBox(height: SelSpace.x1),
          Text(
            headline,
            style: SelType.hero.copyWith(fontSize: 32, color: Sel.card, height: 1.15),
          ),
          Text(sub, style: SelType.body.copyWith(color: soft)),
          const SizedBox(height: SelSpace.x3),
          ...body,
          const SizedBox(height: SelSpace.x4),
          if (action != null)
            Material(
              color: Sel.card,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Text(
                    action!,
                    textAlign: TextAlign.center,
                    style: SelType.button.copyWith(color: Sel.ink),
                  ),
                ),
              ),
            ),
          if (footLink != null) ...[
            const SizedBox(height: SelSpace.x3),
            Center(
              child: InkWell(
                onTap: onFootLink,
                child: Text(
                  footLink!,
                  style: SelType.bodySm.copyWith(
                    color: Sel.card,
                    decoration: TextDecoration.underline,
                    decorationColor: Sel.card,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A card holding a short list: a title, a link to the whole list, an
/// optional line under the title, then rows split by hairlines.
class SelListCard extends StatelessWidget {
  const SelListCard({
    super.key,
    required this.title,
    required this.rows,
    this.link,
    this.onLink,
    this.note,
    this.empty,
    this.after,
  });

  final String title;
  final String? link;
  final VoidCallback? onLink;
  final String? note;
  final List<Widget> rows;

  /// Shown when there are no rows.
  final String? empty;

  /// Anything under the rows: a link, a note.
  final Widget? after;

  @override
  Widget build(BuildContext context) {
    return SelCard(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: SelType.subtitle)),
              if (link != null) SelLink(label: link!, onTap: onLink),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: SelSpace.x1),
            Text(note!, style: SelType.small),
          ],
          const SizedBox(height: SelSpace.x1),
          if (rows.isEmpty && empty != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SelSpace.x4),
              child: Text(empty!, style: SelType.bodySm),
            ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Sel.rowLine),
            rows[i],
          ],
          ?after,
        ],
      ),
    );
  }
}

/// One row of a [SelListCard]: initials, a title and a line under it, and a
/// value on the right with an optional line under that.
class SelListLine extends StatelessWidget {
  const SelListLine({
    super.key,
    required this.title,
    required this.sub,
    this.face,
    this.trailing,
    this.trailingSub,
    this.onTap,
  });

  final String title;
  final String sub;

  /// The name to draw initials from; null draws none.
  final String? face;
  final Widget? trailing;
  final String? trailingSub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            if (face != null) ...[
              SelFace(face!, size: 34),
              const SizedBox(width: SelSpace.x3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: SelType.body.copyWith(color: Sel.text, fontWeight: FontWeight.w600),
                  ),
                  Text(sub, overflow: TextOverflow.ellipsis, style: SelType.small),
                ],
              ),
            ),
            if (trailing != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  trailing!,
                  if (trailingSub != null) Text(trailingSub!, style: SelType.small),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Tabs that each show a count under their label, the chosen one on light
/// sky with a navy underline: Need you 4, Ready 12.
class SelCountTabs<T> extends StatelessWidget {
  const SelCountTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.tabWidth,
  });

  /// Value, label and count for each tab, in order.
  final List<(T, String, int)> tabs;
  final T selected;
  final ValueChanged<T> onSelect;

  /// Fixed width for each tab; null shares the width evenly.
  final double? tabWidth;

  @override
  Widget build(BuildContext context) {
    Widget tab((T, String, int) t) {
      final on = t.$1 == selected;
      return Semantics(
        selected: on,
        button: true,
        child: InkWell(
          onTap: () => onSelect(t.$1),
          child: Container(
            width: tabWidth,
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            decoration: BoxDecoration(
              color: on ? Sel.skyTint : null,
              border: Border(
                bottom: BorderSide(color: on ? Sel.ink : Colors.transparent, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.$2, style: SelType.small),
                Text(
                  '${t.$3}',
                  style: SelType.subtitle.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Sel.border)),
      ),
      child: tabWidth == null
          ? Row(children: [for (final t in tabs) Expanded(child: tab(t))])
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final t in tabs) tab(t)]),
            ),
    );
  }
}

/// Tabs on a light track, the chosen one lifted onto white: the fellowship
/// page's Overview, People, Arms, Month by month.
class SelTrackTabs<T> extends StatelessWidget {
  const SelTrackTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<(T, String)> tabs;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Sel.rail,
        borderRadius: BorderRadius.circular(SelRadius.pill),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (value, label) in tabs)
              Semantics(
                selected: value == selected,
                button: true,
                child: Material(
                  color: value == selected ? Sel.card : Colors.transparent,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: value == selected ? Sel.border : Colors.transparent,
                    ),
                  ),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onSelect(value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        label,
                        style: SelType.bodySm.copyWith(
                          color: value == selected ? Sel.ink : Sel.warm,
                          fontWeight: value == selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The navy bar that acts on rows someone has ticked: how many, a line
/// saying who, Clear, and one white button. Its shadow is a flat light-sky
/// edge, like the buttons.
class SelChoiceBar extends StatelessWidget {
  const SelChoiceBar({
    super.key,
    required this.count,
    required this.action,
    required this.onAction,
    required this.onClear,
    this.note,
    this.busy = false,
  });

  final int count;
  final String? note;
  final String action;
  final VoidCallback onAction;
  final VoidCallback onClear;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Semantics(
      container: true,
      label: '$count chosen',
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
        decoration: BoxDecoration(
          color: Sel.ink,
          borderRadius: BorderRadius.circular(SelRadius.pill),
          boxShadow: const [BoxShadow(color: Sel.skyWash, offset: Offset(0, 5))],
        ),
        child: Row(
          children: [
            Text(
              '$count chosen',
              style: SelType.body.copyWith(color: Sel.card, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: SelSpace.x3),
            Expanded(
              child: compact || note == null
                  ? const SizedBox.shrink()
                  : Text(
                      note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SelType.bodySm.copyWith(color: SelNavyCard.soft),
                    ),
            ),
            TextButton(
              onPressed: busy ? null : onClear,
              style: TextButton.styleFrom(foregroundColor: Sel.card),
              child: Text('Clear', style: SelType.button.copyWith(color: Sel.card)),
            ),
            const SizedBox(width: SelSpace.x2),
            Material(
              color: Sel.card,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: busy ? null : onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Sel.ink),
                        )
                      : Text(action, style: SelType.button.copyWith(color: Sel.ink)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// The bar that holds unsaved changes: what changed, Discard, and Save
/// changes. Pinned at the foot of the page like [SelChoiceBar], so every
/// form in Pillr saves the same way.
class SelSaveBar extends StatelessWidget {
  const SelSaveBar({
    super.key,
    required this.message,
    required this.onSave,
    required this.onDiscard,
    this.busy = false,
  });

  final String message;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
        decoration: BoxDecoration(
          color: Sel.ink,
          borderRadius: BorderRadius.circular(SelRadius.pill),
          boxShadow: const [BoxShadow(color: Sel.skyWash, offset: Offset(0, 5))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: message,
                      style: SelType.body.copyWith(color: Sel.card, fontWeight: FontWeight.w800),
                    ),
                    if (!compact)
                      TextSpan(
                        text: '   Nothing is saved until you press Save changes.',
                        style: SelType.bodySm.copyWith(color: SelNavyCard.soft),
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: busy ? null : onDiscard,
              child: Text('Discard', style: SelType.button.copyWith(color: Sel.card)),
            ),
            const SizedBox(width: SelSpace.x2),
            Material(
              color: Sel.card,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: busy ? null : onSave,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Sel.ink))
                      : Text('Save changes', style: SelType.button.copyWith(color: Sel.ink)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
