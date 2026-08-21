import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';

/// State vocabulary.
///
/// State carries **icon + warm semantic colour + weight**. The icon is still
/// doing the primary work — the palette is desaturated on purpose and the set
/// stays legible without colour — but a blocked row now separates from a
/// settled one at a glance, which pure monochrome could not manage on screens
/// like bulk import where the state *is* the thing to act on.
///
/// | State     | Icon    | Colour  | Reads as         |
/// |-----------|---------|---------|------------------|
/// | approved  | check   | Moss    | settled, correct |
/// | pending   | clock   | Ochre   | waiting on you   |
/// | declined  | x       | Clay    | closed, rejected |
/// | blocked   | alert   | Clay    | cannot proceed   |
/// | active    | dot     | Moss    | live             |
/// | inactive  | dash    | Ash     | dormant          |
/// | info      | circle  | Cyan    | neutral notice   |
enum SelStatus { approved, pending, declined, blocked, active, inactive, info }

extension SelStatusStyle on SelStatus {
  IconData get icon => switch (this) {
        SelStatus.approved => LucideIcons.check,
        SelStatus.pending => LucideIcons.clock,
        SelStatus.declined => LucideIcons.x,
        SelStatus.blocked => LucideIcons.alertTriangle,
        SelStatus.active => LucideIcons.circleDot,
        SelStatus.inactive => LucideIcons.minus,
        SelStatus.info => LucideIcons.info,
      };

  Color get color => switch (this) {
        SelStatus.approved || SelStatus.active => Sel.success,
        SelStatus.pending => Sel.warning,
        SelStatus.declined || SelStatus.blocked => Sel.danger,
        SelStatus.inactive => Sel.ash,
        SelStatus.info => Sel.info,
      };

  /// Chip background. Inactive stays on the canvas — a dormant record should
  /// not draw a wash.
  Color get wash => switch (this) {
        SelStatus.approved || SelStatus.active => Sel.successWash,
        SelStatus.pending => Sel.warningWash,
        SelStatus.declined || SelStatus.blocked => Sel.dangerWash,
        SelStatus.inactive => Sel.canvas,
        SelStatus.info => Sel.infoWash,
      };

  FontWeight get weight => switch (this) {
        SelStatus.approved || SelStatus.active || SelStatus.blocked =>
          FontWeight.w500,
        _ => FontWeight.w400,
      };

  /// Maps a raw Firestore status string. Unknown values fall through to
  /// [SelStatus.pending] rather than throwing.
  static SelStatus parse(String? raw) => switch (raw?.trim().toLowerCase()) {
        // 'accepted' is the invite collection's word for the same settled
        // state that entries call 'approved'.
        'approved' || 'accepted' || 'complete' => SelStatus.approved,
        'declined' || 'rejected' || 'expired' => SelStatus.declined,
        'blocked' || 'error' || 'invalid' => SelStatus.blocked,
        'info' || 'notice' => SelStatus.info,
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
        color: status.wash,
        borderRadius: BorderRadius.circular(SelRadius.pill),
        border: Border.all(
          color: status == SelStatus.inactive
              ? Sel.border
              : status.color.withValues(alpha: 0.22),
        ),
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
