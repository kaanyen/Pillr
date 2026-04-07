import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';

class Partner {
  const Partner({
    required this.id,
    required this.churchId,
    required this.memberId,
    required this.fullName,
    required this.fellowship,
    this.email,
    this.phone,
    required this.isActive,
    required this.totalApprovedAmount,
    required this.entryCount,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String churchId;
  final String memberId;
  final String fullName;
  final String fellowship;
  final String? email;
  final String? phone;
  final bool isActive;
  final double totalApprovedAmount;
  final int entryCount;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayLabel => '$memberId · $fullName · $fellowship';

  factory Partner.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Partner(
      id: d.id,
      churchId: m['churchId'] as String? ?? '',
      memberId: m['memberId'] as String? ?? '',
      fullName: m['fullName'] as String? ?? '',
      fellowship: m['fellowship'] as String? ?? '',
      email: m['email'] as String?,
      phone: m['phone'] as String?,
      isActive: m['isActive'] as bool? ?? true,
      totalApprovedAmount: (m['totalApprovedAmount'] as num?)?.toDouble() ?? 0,
      entryCount: (m['entryCount'] as num?)?.toInt() ?? 0,
      createdBy: m['createdBy'] as String? ?? '',
      createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
      updatedAt: timestampToDateTime(m['updatedAt']) ?? DateTime.now(),
    );
  }
}
