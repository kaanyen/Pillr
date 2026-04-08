import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/firebase_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/domain/church_user.dart';

class UsersRepository {
  UsersRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> _users(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('users');
  }

  Stream<List<ChurchUser>> watchUsers(String churchId) {
    return _users(churchId).orderBy('fullName').snapshots().map(
          (snap) => snap.docs.map(ChurchUser.fromSnapshot).whereType<ChurchUser>().toList(),
        );
  }

  Future<void> updateMember({
    required String churchId,
    required String targetUid,
    bool? isActive,
    String? role,
  }) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.updateChurchMember);
      await callable.call(<String, dynamic>{
        'churchId': churchId,
        'targetUid': targetUid,
        if (isActive != null) 'isActive': isActive,
        if (role != null) 'role': role,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not update member.', code: e.code);
    }
  }
}
