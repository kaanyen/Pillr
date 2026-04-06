import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/firebase_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/invite_models.dart';

class InviteRepository {
  InviteRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Stream<List<InviteRecord>> watchInvites(String churchId) {
    return _firestore
        .collection('churches')
        .doc(churchId)
        .collection('invite_codes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) {
        final m = d.data();
        return InviteRecord(
          id: d.id,
          code: m['code'] as String? ?? '',
          email: m['email'] as String? ?? '',
          role: m['role'] as String? ?? 'staff',
          createdBy: m['createdBy'] as String? ?? '',
          createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
          expiresAt: timestampToDateTime(m['expiresAt']) ?? DateTime.now(),
          status: m['status'] as String? ?? 'pending',
          createdByName: (m['createdBySnapshot'] as Map?)?.cast<String, dynamic>()['fullName'] as String?,
        );
      }).toList();
    });
  }

  Future<void> sendInvite({
    required String churchId,
    required String email,
    required String role,
  }) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.generateInviteCode);
      await callable.call(<String, dynamic>{
        'churchId': churchId,
        'email': email.trim(),
        'role': role,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not send invite.', code: e.code);
    }
  }

  Future<void> deleteInvite({required String churchId, required String inviteId}) {
    return _firestore
        .collection('churches')
        .doc(churchId)
        .collection('invite_codes')
        .doc(inviteId)
        .delete();
  }
}
