import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';

class PartnershipPeriod {
  const PartnershipPeriod({
    required this.id,
    required this.churchId,
    required this.name,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.totalApprovedAmount,
    required this.entryCount,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String churchId;
  final String name;
  final String? description;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final double totalApprovedAmount;
  final int entryCount;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PartnershipPeriod.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return PartnershipPeriod(
      id: d.id,
      churchId: m['churchId'] as String? ?? '',
      name: m['name'] as String? ?? '',
      description: m['description'] as String?,
      startDate: timestampToDateTime(m['startDate']) ?? DateTime.now(),
      endDate: timestampToDateTime(m['endDate']) ?? DateTime.now(),
      isActive: m['isActive'] as bool? ?? false,
      totalApprovedAmount: (m['totalApprovedAmount'] as num?)?.toDouble() ?? 0,
      entryCount: (m['entryCount'] as num?)?.toInt() ?? 0,
      createdBy: m['createdBy'] as String? ?? '',
      createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
      updatedAt: timestampToDateTime(m['updatedAt']) ?? DateTime.now(),
    );
  }
}
