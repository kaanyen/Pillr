import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';

class PartnershipGoal {
  const PartnershipGoal({
    required this.id,
    required this.churchId,
    required this.partnershipPeriodId,
    required this.partnershipArmId,
    required this.targetAmountCedis,
    required this.currentAmountCedis,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String churchId;
  final String partnershipPeriodId;
  final String partnershipArmId;
  final double targetAmountCedis;
  final double currentAmountCedis;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get progressFraction =>
      targetAmountCedis <= 0 ? 0 : (currentAmountCedis / targetAmountCedis).clamp(0.0, 1.0);

  factory PartnershipGoal.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return PartnershipGoal(
      id: d.id,
      churchId: m['churchId'] as String? ?? '',
      partnershipPeriodId: m['partnershipPeriodId'] as String? ?? '',
      partnershipArmId: m['partnershipArmId'] as String? ?? '',
      targetAmountCedis: (m['targetAmountCedis'] as num?)?.toDouble() ?? 0,
      currentAmountCedis: (m['currentAmountCedis'] as num?)?.toDouble() ?? 0,
      createdBy: m['createdBy'] as String? ?? '',
      createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
      updatedAt: timestampToDateTime(m['updatedAt']) ?? DateTime.now(),
    );
  }
}
