import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/extensions/async_value_ext.dart';
import '../../core/utils/date_utils.dart';
import '../auth/providers/auth_providers.dart';

/// A bulk change on record: a fellowship merge, move or dissolve, or a
/// partner merge. Written by the server with every document's before and
/// after, so it can be undone.
class RecordOperation {
  const RecordOperation({
    required this.id,
    required this.kind,
    required this.status,
    required this.summary,
    required this.planned,
    required this.applied,
    required this.actorName,
    required this.createdAt,
    this.undoConflictCount = 0,
  });

  final String id;
  final String kind;

  /// applying, applied, failed, undoing, undone.
  final String status;
  final Map<String, dynamic> summary;
  final int planned;
  final int applied;
  final String actorName;
  final DateTime createdAt;
  final int undoConflictCount;

  bool get canUndo => status == 'applied' || status == 'failed';

  /// One line a pastor recognises: what changed, in their words.
  String get label {
    final s = summary;
    String v(String k) => (s[k] ?? '').toString();
    switch (kind) {
      case 'fellowship.merge':
        return 'Merged ${v('from')} into ${v('to')}';
      case 'fellowship.rename':
        return 'Renamed ${v('from')} to ${v('to')}';
      case 'fellowship.dissolve':
        return 'Dissolved ${v('from')} into ${v('to')}';
      case 'fellowship.move':
        return 'Moved partners from ${v('from')} to ${v('to')}';
      case 'partner.merge':
        final ids = v('newMemberId');
        return 'Merged ${v('absorbedName')} into ${v('keptName')}'
            '${ids.isEmpty ? '' : ' (new ID $ids)'}';
      case 'partner.unmerge':
        return 'Separated ${v('separatedName')} (${v('separatedMemberId')}) '
            'from ${v('keptName')}';
      default:
        return kind;
    }
  }

  factory RecordOperation.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final actor = (m['actorSnapshot'] as Map?)?.cast<String, dynamic>() ?? {};
    return RecordOperation(
      id: d.id,
      kind: m['kind'] as String? ?? '',
      status: m['status'] as String? ?? '',
      summary: (m['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
      planned: (m['planned'] as num?)?.toInt() ?? 0,
      applied: (m['applied'] as num?)?.toInt() ?? 0,
      actorName: actor['fullName'] as String? ?? '',
      createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
      undoConflictCount: (m['undoConflictCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The server side of fellowship and partner merges. See
/// functions/src/record_ops.ts — the rules no longer allow these writes from
/// the app.
class RecordOpsRepository {
  RecordOpsRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _functions.httpsCallable(name).call(data);
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'The change did not go through.', code: e.code);
    }
  }

  /// [kind] is merge, rename, dissolve or move. [expectActive] is how many
  /// active partners the person saw moving; the server refuses if that is no
  /// longer true.
  Future<FellowshipChangeResult> fellowshipChange({
    required String churchId,
    required String kind,
    required String toName,
    List<String> fromNames = const [],
    List<String> partnerIds = const [],
    int? expectActive,
  }) async {
    final r = await _call(FirebaseConstants.fellowshipChange, {
      'churchId': churchId,
      'kind': kind,
      'toName': toName,
      'fromNames': fromNames,
      'partnerIds': partnerIds,
      'expectActive': ?expectActive,
    });
    return FellowshipChangeResult(
      opId: r['opId'] as String?,
      moved: (r['moved'] as num?)?.toInt() ?? 0,
      inactiveMoved: (r['inactiveMoved'] as num?)?.toInt() ?? 0,
    );
  }

  /// Moves every [absorbIds] record's entries onto [keepId] and closes them.
  ///
  /// The kept person gets a new member ID; every old one stays attached to
  /// them in `formerMemberIds`.
  Future<PartnerMergeResult> partnerMerge({
    required String churchId,
    required String keepId,
    required List<String> absorbIds,
    /// How many entries the person was told will move; null when they were
    /// not told (staff and admins do not read every entry).
    int? expectEntries,
  }) async {
    final r = await _call(FirebaseConstants.partnerMerge, {
      'churchId': churchId,
      'keepId': keepId,
      'absorbIds': absorbIds,
      'expectEntries': ?expectEntries,
    });
    return PartnerMergeResult(
      opId: r['opId'] as String?,
      moved: (r['moved'] as num?)?.toInt() ?? 0,
      filled: [for (final f in (r['filled'] as List? ?? const [])) f.toString()],
      newMemberId: r['newMemberId'] as String? ?? '',
      formerMemberIds: [
        for (final f in (r['formerMemberIds'] as List? ?? const [])) f.toString(),
      ],
    );
  }

  /// Takes the record with [memberId] back out of the merge it is in.
  Future<({int moved, String partnerId})> partnerUnmerge({
    required String churchId,
    required String memberId,
  }) async {
    final r = await _call(FirebaseConstants.partnerUnmerge, {
      'churchId': churchId,
      'memberId': memberId,
    });
    return (
      moved: (r['moved'] as num?)?.toInt() ?? 0,
      partnerId: r['partnerId'] as String? ?? '',
    );
  }

  Future<({int reverted, int conflicts})> undo({
    required String churchId,
    required String opId,
  }) async {
    final r = await _call(FirebaseConstants.undoOperation, {
      'churchId': churchId,
      'opId': opId,
    });
    return (
      reverted: (r['reverted'] as num?)?.toInt() ?? 0,
      conflicts: (r['conflicts'] as num?)?.toInt() ?? 0,
    );
  }

  Stream<List<RecordOperation>> watchRecent(String churchId, {int limit = 20}) {
    return _firestore
        .collection('churches')
        .doc(churchId)
        .collection('operations')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(RecordOperation.fromDoc).toList());
  }
}

class PartnerMergeResult {
  const PartnerMergeResult({
    required this.opId,
    required this.moved,
    required this.filled,
    required this.newMemberId,
    required this.formerMemberIds,
  });

  final String? opId;
  final int moved;
  final List<String> filled;
  final String newMemberId;
  final List<String> formerMemberIds;
}

class FellowshipChangeResult {
  const FellowshipChangeResult({
    required this.opId,
    required this.moved,
    required this.inactiveMoved,
  });

  final String? opId;

  /// Active partners moved.
  final int moved;

  /// Inactive partners moved with them, so they do not keep the old name.
  final int inactiveMoved;
}

final recordOpsRepositoryProvider = Provider<RecordOpsRepository>((ref) {
  return RecordOpsRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseFunctionsProvider),
  );
});

final recentOperationsProvider =
    StreamProvider.autoDispose<List<RecordOperation>>((ref) {
      final idx = ref.watch(userChurchIndexProvider).valueOrNull;
      if (idx == null) return Stream.value(const []);
      return ref.watch(recordOpsRepositoryProvider).watchRecent(idx.churchId);
    });
