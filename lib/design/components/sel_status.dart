import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';

/// Monochrome state vocabulary.
///
/// Seline spends its whole chromatic budget on the cyan action, so state gets
/// none of it. Status reads through **icon + neutral weight** instead:
///
/// | State     | Icon    | Colour    | Weight | Reads as        |
/// |-----------|---------|-----------|--------|-----------------|
/// | approved  | check   | Ink       | 500    | settled, final  |
/// | pending   | clock   | Warm gray | 400    | waiting on you  |
/// | declined  | x       | Ash gray  | 400    | closed          |
/// | active    | dot     | Ink       | 500    | live            |
/// | inactive  | dash    | Ash gray  | 400    | dormant         |
///
/// This is also the colourblind-safe arrangement: the glyph carries the
/// meaning, the tone only reinforces it.
enum SelStatus { approved, pending, declined, active, inactive }

extension SelStatusStyle on SelStatus {
  IconData get icon => switch (this) {
        SelStatus.approved => LucideIcons.check,
        SelStatus.pending => LucideIcons.clock,
        SelStatus.declined => LucideIcons.x,
        SelStatus.active => LucideIcons.circleDot,
        SelStatus.inactive => LucideIcons.minus,
      };

  Color get color => switch (this) {
        SelStatus.approved => Sel.ink,
        SelStatus.pending => Sel.warm,
        SelStatus.declined => Sel.ash,
        SelStatus.active => Sel.ink,
        SelStatus.inactive => Sel.ash,
      };

  FontWeight get weight => switch (this) {
        SelStatus.approved || SelStatus.active => FontWeight.w500,
        _ => FontWeight.w400,
      };

  /// Maps a raw Firestore status string. Unknown values fall through to
  /// [SelStatus.pending] rather than throwing.
  static SelStatus parse(String? raw) => switch (raw?.trim().toLowerCase()) {
        // 'accepted' is the invite collection's word for the same settled
        // state that entries call 'approved'.
        'approved' || 'accepted' || 'complete' => SelStatus.approved,
        'declined' || 'rejected' || 'expired' => SelStatus.declined,
        'active' => SelStatus.active,
        'inactive' || 'suspended' => SelStatus.inactive,
        _ => SelStatus.pending,
      };
}

/// Inline status mark: glyph + label, no chip, no fill.
///
/// Deliberately chrome-less so a long ledger does not turn into a wall of
/// pills. Use [SelStatusChip] only where a row needs a harder edge.
class SelStatusMark extends StatelessWidget {
  const SelStatusMark({
    super.key,
    required this.status,
    required this.label,
    this.iconOnly = false,
  });

  SelStatusMark.fromString({
    super.key,
    required String? status,
    required this.label,
    this.iconOnly = false,
  }) : status = SelStatusStyle.parse(status);

  final SelStatus status;
  final String label;

  /// Drop the label — for very narrow columns. Keeps a tooltip for meaning.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(status.icon, size: 13, color: status.color),
        if (!iconOnly) ...[
          const SizedBox(width: SelSpace.x1 + 2),
          Text(
            label,
            style: SelType.body.copyWith(
              color: status.color,
              fontWeight: status.weight,
            ),
          ),
        ],
      ],
    );
    return iconOnly ? Tooltip(message: label, child: mark) : mark;
  }
}

/// Bordered variant, for cases where the status must survive on a busy row.
class SelStatusChip extends StatelessWidget {
  const SelStatusChip({super.key, required this.status, required this.label});

  SelStatusChip.fromString({super.key, required String? status, required this.label})
      : status = SelStatusStyle.parse(status);

  final SelStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SelSpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: Sel.canvas,
        borderRadius: BorderRadius.circular(SelRadius.pill),
        border: Border.all(color: Sel.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 11, color: status.color),
          const SizedBox(width: SelSpace.x1),
          Text(
            label,
            style: SelType.tag.copyWith(
              color: status.color,
              fontWeight: status.weight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral count tag. [emphasised] inverts to Soot for a figure that needs
/// attention — the pending queue count, for instance.
class SelCountTag extends StatelessWidget {
  const SelCountTag({super.key, required this.label, this.emphasised = false});

  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SelSpace.x2, vertical: 1),
      decoration: BoxDecoration(
        color: emphasised ? Sel.soot : Sel.canvas,
        borderRadius: BorderRadius.circular(SelRadius.pill),
        border: emphasised ? null : Border.all(color: Sel.border),
      ),
      child: Text(
        label,
        style: SelType.tag.copyWith(color: emphasised ? Sel.card : Sel.warm),
      ),
    );
  }
}
