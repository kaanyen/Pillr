import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/color_utils.dart';
import '../design/seline.dart';
import '../features/arms/providers/arms_providers.dart';

/// Stable colour per partnership arm, assigned by position.
///
/// Hashing the arm id was the obvious approach and it was wrong: with four
/// arms drawing from eight swatches, two pairs collided and the dots stopped
/// distinguishing anything. Assigning by the arm's `sortOrder` guarantees
/// every arm in a church gets a different swatch, up to the palette size.
///
/// A church that has set its own `colorHex` on an arm keeps that colour; the
/// palette only fills in the ones that have none.
final armColorsProvider = Provider<Map<String, Color>>((ref) {
  final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
  final ordered = [...arms]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  final map = <String, Color>{};
  var next = 0;
  for (final arm in ordered) {
    final stored = parseHexColor(arm.colorHex);
    if (stored != null) {
      map[arm.id] = stored;
    } else {
      map[arm.id] = Sel.armPalette[next % Sel.armPalette.length];
      next++;
    }
  }
  return map;
});

/// Colour for [armId], falling back to the id-derived swatch when the arm is
/// not in the current stream (a deleted arm still named on an old entry).
Color armColorOf(WidgetRef ref, String armId) =>
    ref.watch(armColorsProvider)[armId] ?? Sel.armColor(armId);

/// A small filled dot in the arm's colour, sized to sit inline with 14px text.
class ArmDot extends ConsumerWidget {
  const ArmDot({super.key, required this.armId, this.size = 6});

  final String armId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: armColorOf(ref, armId),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Arm name preceded by its dot — the standard way an arm appears in a row.
class ArmLabel extends ConsumerWidget {
  const ArmLabel({
    super.key,
    required this.armId,
    required this.name,
    this.style,
  });

  final String armId;
  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ArmDot(armId: armId),
        const SizedBox(width: SelSpace.x2),
        Flexible(
          child: Text(
            name,
            style: style ?? SelType.bodyMuted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
