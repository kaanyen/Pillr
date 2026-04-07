import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';

class PartnershipEntry {
  const PartnershipEntry({
    required this.id,
    required this.churchId,
    required this.partnerId,
    required this.partnerSnapshot,
    required this.partnershipArmId,
    required this.armSnapshot,
    required this.partnershipPeriodId,
    required this.periodSnapshot,
    required this.amountCedis,
    required this.dateGiven,
    this.notes,
    required this.status,
    required this.createdBy,
    required this.createdBySnapshot,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
    this.reviewedBySnapshot,
    this.reviewedAt,
    this.declineReason,
    this.editHistory = const [],
  });

  final String id;
  final String churchId;
  final String partnerId;
  final Map<String, dynamic> partnerSnapshot;
  final String partnershipArmId;
  final Map<String, dynamic> armSnapshot;
  final String partnershipPeriodId;
  final Map<String, dynamic> periodSnapshot;
  final double amountCedis;
  final DateTime dateGiven;
  final String? notes;
  final String status;
  final String createdBy;
  final Map<String, dynamic> createdBySnapshot;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reviewedBy;
  final Map<String, dynamic>? reviewedBySnapshot;
  final DateTime? reviewedAt;
  final String? declineReason;
  final List<Map<String, dynamic>> editHistory;

  factory PartnershipEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return PartnershipEntry(
      id: d.id,
      churchId: m['churchId'] as String? ?? '',
      partnerId: m['partnerId'] as String? ?? '',
      partnerSnapshot: Map<String, dynamic>.from(m['partnerSnapshot'] as Map? ?? {}),
      partnershipArmId: m['partnershipArmId'] as String? ?? '',
      armSnapshot: Map<String, dynamic>.from(m['armSnapshot'] as Map? ?? {}),
      partnershipPeriodId: m['partnershipPeriodId'] as String? ?? '',
      periodSnapshot: Map<String, dynamic>.from(m['periodSnapshot'] as Map? ?? {}),
      amountCedis: (m['amountCedis'] as num?)?.toDouble() ?? 0,
      dateGiven: timestampToDateTime(m['dateGiven']) ?? DateTime.now(),
      notes: m['notes'] as String?,
      status: m['status'] as String? ?? 'pending',
      createdBy: m['createdBy'] as String? ?? '',
      createdBySnapshot: Map<String, dynamic>.from(m['createdBySnapshot'] as Map? ?? {}),
      createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
      updatedAt: timestampToDateTime(m['updatedAt']) ?? DateTime.now(),
      reviewedBy: m['reviewedBy'] as String?,
      reviewedBySnapshot: m['reviewedBySnapshot'] != null
          ? Map<String, dynamic>.from(m['reviewedBySnapshot'] as Map)
          : null,
      reviewedAt: timestampToDateTime(m['reviewedAt']),
      declineReason: m['declineReason'] as String?,
      editHistory: (m['editHistory'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
    );
  }
}
