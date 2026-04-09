import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';
import '../../../core/utils/text_case_utils.dart';

/// Row from `churches/{churchId}/activity_logs/{logId}`.
class ActivityLogRow {
  const ActivityLogRow({
    required this.id,
    required this.churchId,
    required this.actorUid,
    required this.actorSnapshot,
    required this.action,
    required this.entityType,
    this.entityId,
    this.entitySnapshot,
    this.metadata,
    required this.createdAt,
  });

  final String id;
  final String churchId;
  final String actorUid;
  final Map<String, dynamic> actorSnapshot;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? entitySnapshot;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  String get actorName => actorSnapshot['fullName']?.toString() ?? actorUid;
  String get actorRole => actorSnapshot['role']?.toString() ?? '';

  factory ActivityLogRow.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return ActivityLogRow(
      id: d.id,
      churchId: m['churchId'] as String? ?? '',
      actorUid: m['actorUid'] as String? ?? '',
      actorSnapshot: Map<String, dynamic>.from(m['actorSnapshot'] as Map? ?? {}),
      action: m['action'] as String? ?? '',
      entityType: m['entityType'] as String? ?? '',
      entityId: m['entityId'] as String?,
      entitySnapshot: m['entitySnapshot'] != null
          ? TextCaseUtils.normalizeLooseEntitySnapshot(
              Map<String, dynamic>.from(m['entitySnapshot'] as Map),
            )
          : null,
      metadata: m['metadata'] != null ? Map<String, dynamic>.from(m['metadata'] as Map) : null,
      createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
    );
  }
}
