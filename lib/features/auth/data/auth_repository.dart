import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/firebase_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/invite_models.dart';

class AuthRepository {
  AuthRepository(this._auth, this._functions);

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signInWithEmail({required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<BootstrapValidationResult> validateBootstrapInvite({
    required String email,
    required String code,
  }) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.validateBootstrapInvite);
      final res = await callable.call(<String, dynamic>{
        'email': email.trim(),
        'code': code.trim().toUpperCase(),
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      final valid = data['valid'] == true;
      if (!valid) {
        return BootstrapValidationResult(
          valid: false,
          errorMessage: data['message'] as String? ?? 'Invalid or expired setup code.',
        );
      }
      return BootstrapValidationResult(
        valid: true,
        role: data['role'] as String?,
        inviteId: data['inviteId'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      return BootstrapValidationResult(
        valid: false,
        errorMessage: e.message ?? 'Could not verify setup code.',
      );
    }
  }

  Future<void> redeemBootstrapInvite({
    required String fullName,
    required String phone,
    required String code,
    required String churchName,
    required String currency,
    required String currencySymbol,
  }) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.redeemBootstrapInvite);
      await callable.call(<String, dynamic>{
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'code': code.trim().toUpperCase(),
        'churchName': churchName.trim(),
        'currency': currency,
        'currencySymbol': currencySymbol,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not finish church setup.', code: e.code);
    }
  }

  Future<InviteValidationResult> validateInvite({
    required String email,
    required String code,
  }) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.validateInviteCode);
      final res = await callable.call(<String, dynamic>{
        'email': email.trim(),
        'code': code.trim().toUpperCase(),
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      final valid = data['valid'] == true;
      if (!valid) {
        return InviteValidationResult(
          valid: false,
          errorMessage: data['message'] as String? ?? 'Invalid or expired invitation.',
        );
      }
      return InviteValidationResult(
        valid: true,
        churchName: data['churchName'] as String?,
        churchId: data['churchId'] as String?,
        role: data['role'] as String?,
        codeId: data['codeId'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      return InviteValidationResult(
        valid: false,
        errorMessage: e.message ?? 'Could not verify invitation.',
      );
    }
  }

  Future<UserCredential> createAuthUser({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> completeRegistration({
    required String fullName,
    required String phone,
    required String codeId,
    required String churchId,
  }) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.completeRegistration);
      await callable.call(<String, dynamic>{
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'codeId': codeId,
        'churchId': churchId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Registration failed.', code: e.code);
    }
  }

  /// Roll back Auth user if Firestore registration fails after account creation.
  Future<void> deleteCurrentUser() async {
    await _auth.currentUser?.delete();
  }
}
