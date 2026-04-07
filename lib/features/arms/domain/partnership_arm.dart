import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';

class PartnershipArm {
  const PartnershipArm({
    required this.id,
    required this.churchId,
    required this.name,
    this.description,
    required this.isActive,
    this.colorHex,
    required this.sortOrder,
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
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PartnershipArm.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return PartnershipArm(
      id: d.id,
      churchId: m['churchId'] as String? ?? '',
      name: m['name'] as String? ?? '',
      description: m['description'] as String?,
      isActive: m['isActive'] as bool? ?? true,
      colorHex: m['colorHex'] as String?,
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
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
