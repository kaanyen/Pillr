import 'partnership_arm.dart';

/// Main arms and the sub-arms that count toward them.
///
/// Built from the flat arm list on every read, so nothing about the grouping
/// is stored twice. A sub-arm whose main arm is missing (deleted, or not loaded
/// yet) is treated as a main arm rather than vanishing from the list.
class ArmTree {
  ArmTree(List<PartnershipArm> arms) {
    final ordered = [...arms]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final ids = {for (final a in ordered) a.id};
    for (final a in ordered) {
      _byId[a.id] = a;
      final parent = a.parentArmId;
      if (parent != null && parent != a.id && ids.contains(parent)) {
        _children.putIfAbsent(parent, () => []).add(a);
      } else {
        _mains.add(a);
      }
    }
  }

  final _byId = <String, PartnershipArm>{};
  final _mains = <PartnershipArm>[];
  final _children = <String, List<PartnershipArm>>{};

  /// Main arms (and arms with no main), in sort order.
  List<PartnershipArm> get mains => List.unmodifiable(_mains);

  /// Sub-arms of [armId], in sort order. Empty for a sub-arm.
  List<PartnershipArm> childrenOf(String armId) =>
      List.unmodifiable(_children[armId] ?? const []);

  bool hasChildren(String armId) => _children[armId]?.isNotEmpty ?? false;

  PartnershipArm? byId(String id) => _byId[id];

  /// The main arm [armId] counts toward, or null if it is a main arm itself.
  PartnershipArm? mainOf(String armId) {
    final parent = _byId[armId]?.parentArmId;
    if (parent == null || !_children.containsKey(parent)) return null;
    return _byId[parent];
  }

  /// The arm [armId]'s giving is shown under everywhere outside
  /// Configuration: its main arm, or itself when it is a main arm. Unknown ids
  /// come back unchanged.
  String shownArmIdOf(String armId) => mainOf(armId)?.id ?? armId;

  /// Name to show for [armId] outside Configuration (see [shownArmIdOf]), or
  /// null when the arm isn't in the list.
  String? shownNameOf(String armId) => _byId[shownArmIdOf(armId)]?.name;

  /// "Venue · Logistics" for a sub-arm, "Venue" for a main arm. For the one
  /// place an entry's exact arm is worth showing: its own page.
  String? fullNameOf(String armId) {
    final arm = _byId[armId];
    if (arm == null) return null;
    final main = mainOf(armId);
    return main == null ? arm.name : '${main.name} · ${arm.name}';
  }

  /// [armId] and every sub-arm under it: the arms whose giving counts toward
  /// [armId]. For a sub-arm, just itself.
  Set<String> familyOf(String armId) => {
        armId,
        for (final c in _children[armId] ?? const <PartnershipArm>[]) c.id,
      };

  /// Every arm in display order: each main arm followed by its sub-arms.
  List<({PartnershipArm arm, bool isSub})> get flattened => [
        for (final m in _mains) ...[
          (arm: m, isSub: false),
          for (final c in _children[m.id] ?? const <PartnershipArm>[])
            (arm: c, isSub: true),
        ],
      ];

  /// Arms to record giving to, in display order, each labelled the way a
  /// recording picker shows it: "Venue", then "Venue · Logistics" beneath.
  /// Limited to [allowed] when given (e.g. only active arms).
  List<(PartnershipArm, String)> recordingOptions([Iterable<PartnershipArm>? allowed]) {
    final ids = allowed == null ? null : {for (final a in allowed) a.id};
    return [
      for (final r in flattened)
        if (ids == null || ids.contains(r.arm.id))
          (r.arm, r.isSub ? fullNameOf(r.arm.id)! : r.arm.name),
    ];
  }

  /// Why [armId] can't be placed under [newParentId], or null if it can.
  ///
  /// One level only, so an arm that already has sub-arms can't become one,
  /// and nothing can go under a sub-arm.
  String? whyCannotMoveUnder(String armId, String newParentId) {
    if (armId == newParentId) return 'An arm can\'t count toward itself.';
    final arm = _byId[armId];
    final parent = _byId[newParentId];
    if (arm == null || parent == null) return 'That arm is no longer there.';
    if (parent.parentArmId != null && _children.containsKey(parent.parentArmId)) {
      return '${parent.name} is already a sub-arm. Sub-arms can\'t have their own.';
    }
    if (hasChildren(armId)) {
      return '${arm.name} has sub-arms of its own. Move them out first.';
    }
    return null;
  }
}

/// Where one arm sits: which main arm it counts toward, and its place in the
/// list.
class ArmPlacement {
  const ArmPlacement({
    required this.armId,
    required this.parentArmId,
    required this.sortOrder,
  });

  final String armId;
  final String? parentArmId;
  final int sortOrder;
}

extension ArmTreeMoves on ArmTree {
  /// The writes that put [armId] under [newParentId] (or make it a main arm
  /// when null), placed last in its new group.
  ///
  /// Every arm is renumbered in display order, but only arms whose main arm
  /// or position actually changed are returned, so a move touches as few
  /// documents as it can. Arms not being moved keep their stored main arm
  /// exactly as it is.
  List<ArmPlacement> placementsForMove(String armId, String? newParentId) {
    final order = [for (final r in flattened) r.arm];
    final moving = order.where((a) => a.id == armId).firstOrNull;
    if (moving == null) return const [];
    order.remove(moving);

    var insertAt = order.length;
    if (newParentId != null) {
      final lastInGroup = order.lastIndexWhere(
        (a) => a.id == newParentId || a.parentArmId == newParentId,
      );
      if (lastInGroup >= 0) insertAt = lastInGroup + 1;
    }
    order.insert(insertAt, moving);

    return [
      for (var i = 0; i < order.length; i++)
        if (order[i].id == armId
            ? (order[i].parentArmId != newParentId || order[i].sortOrder != i)
            : order[i].sortOrder != i)
          ArmPlacement(
            armId: order[i].id,
            parentArmId: order[i].id == armId ? newParentId : order[i].parentArmId,
            sortOrder: i,
          ),
    ];
  }

  /// The writes that would put back how [placements]' arms were before.
  List<ArmPlacement> undoOf(List<ArmPlacement> placements) => [
        for (final p in placements)
          if (byId(p.armId) case final arm?)
            ArmPlacement(
              armId: arm.id,
              parentArmId: arm.parentArmId,
              sortOrder: arm.sortOrder,
            ),
      ];
}
