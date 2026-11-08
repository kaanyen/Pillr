import 'package:firebase_auth/firebase_auth.dart';

import 'plain_error.dart';

String humanizeAuthException(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return plainError(e);
    }
  }
  return plainError(e);
}
