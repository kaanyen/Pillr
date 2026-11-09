import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';
import '../../../core/utils/text_case_utils.dart';

class PartnershipArm {
  const PartnershipArm({
    required this.id,
    required this.churchId,
    required this.name,
    this.description,
    required this.isActive,
    this.colorHex,
    required this.sortOrder,
    this.aliases = const [],
    this.parentArmId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String churchId;
  final String name;
  final String? description;
  final bool isActive;
  final String? colorHex;
  final int sortOrder;

  /// Spreadsheet spellings a church has already mapped to this arm.
  ///
  /// Bulk import writes here when someone resolves an unmatched value, so the
  /// same wording resolves by itself next month. Stored normalised (lowercase,
  /// collapsed whitespace) because that is how they are compared.
  final List<String> aliases;

  /// The main arm this one counts toward, or null for a main arm.
  ///
  /// One level only: a main arm can have sub-arms, a sub-arm cannot. Giving
  /// recorded to a sub-arm stays on that sub-arm's entries; the main arm's
  /// figures are its own giving plus its sub-arms', added up when shown.
  final String? parentArmId;

  bool get isSubArm => parentArmId != null;

  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PartnershipArm.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return PartnershipArm(
      id: d.id,
      churchId: m['churchId'] as String? ?? '',
      name: TextCaseUtils.toTitleCase(m['name'] as String? ?? ''),
      description: m['description'] as String?,
      isActive: m['isActive'] as bool? ?? true,
      colorHex: m['colorHex'] as String?,
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      aliases: ((m['aliases'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      parentArmId: trimOrNull(m['parentArmId'] as String?),
      createdBy: m['createdBy'] as String? ?? '',
      createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
      updatedAt: timestampToDateTime(m['updatedAt']) ?? DateTime.now(),
    );
  }

}

String? normalizeArmColorHex(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var s = raw.trim();
  if (!s.startsWith('#')) s = '#$s';
  if (s.length != 7) return null;
  final hex = s.substring(1);
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return '#${hex.toUpperCase()}';
}

String? trimOrNull(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}
