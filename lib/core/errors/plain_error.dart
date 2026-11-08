import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app_exception.dart';

/// What a person sees when something goes wrong: what happened and what to
/// do, in plain words. Never a code like `[firebase_storage/unauthorized]`,
/// a class name or a stack trace.
///
/// Errors written by Pillr's own server are already plain sentences
/// ("A backup started less than an hour ago…"), so those are kept; what the
/// platform says is replaced.
String plainError(Object? e) {
  if (e == null) return _generic;
  if (e is FirebaseFunctionsException) {
    final m = e.message?.trim() ?? '';
    if (_isOurs(m) && e.code != 'internal' && e.code != 'unknown') return m;
    return _forCode(e.code);
  }
  if (e is FirebaseException) return _forCode(e.code, plugin: e.plugin);
  if (e is AppException) {
    final m = e.message.trim();
    if (_isOurs(m)) return m;
    if (e.code != null) return _forCode(e.code!);
    return plainErrorText(m);
  }
  if (e is TimeoutException) return _slow;
  if (e is FormatException) {
    return "Pillr couldn't read that. Check what you entered or the file you chose, and try again.";
  }
  return plainErrorText(e.toString());
}

/// The same for a message that has already become text, such as one kept in
/// a field and shown later. Plain sentences pass through; technical ones are
/// replaced.
String plainErrorText(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return _generic;
  // "[plugin/code] message", as the Firebase plugins put it.
  final coded = RegExp(r'\[([a-z_]+)/([a-z-]+)\]').firstMatch(s);
  if (coded != null) return _forCode(coded.group(2)!, plugin: coded.group(1));
  final lower = s.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('failed to fetch') ||
      lower.contains('connection')) {
    return _offline;
  }
  if (lower.contains('timeout') || lower.contains('timed out') || lower.contains('deadline')) {
    return _slow;
  }
  if (lower.contains('permission') || lower.contains('unauthorized') || lower.contains('not authorized')) {
    return _forCode('permission-denied');
  }
  // A message someone wrote for people: keep it, without a leading
  // "Exception: ".
  final cleaned = s.replaceFirst(RegExp(r'^(Exception|Error|AppException):\s*'), '');
  if (_isOurs(cleaned)) return cleaned;
  return _generic;
}

const _generic =
    "That didn't work, and it isn't something you did. Try again. "
    'If it keeps happening, tell whoever runs Pillr what you were doing.';
const _offline = "Pillr can't be reached. Check your internet connection and try again.";
const _slow = 'That took too long. Check your internet connection and try again.';
const _permission =
    "Pillr didn't let you do that. Your role may not include it. "
    'If you think it should, sign out and back in, then ask your church admin.';

/// Plain words for each code the Firebase plugins and Pillr's server use.
String _forCode(String code, {String? plugin}) => switch (code) {
  'permission-denied' || 'unauthorized' => _permission,
  'unauthenticated' || 'user-token-expired' || 'requires-recent-login' =>
    "You've been signed out. Sign in again, then try once more.",
  'unavailable' || 'network-request-failed' || 'retry-limit-exceeded' => _offline,
  'deadline-exceeded' => _slow,
  'not-found' || 'object-not-found' =>
    "That's no longer there. It may have been changed or removed. Refresh the page and look again.",
  'already-exists' => 'That already exists, so nothing new was added.',
  'aborted' => 'Someone else changed this at the same moment. Try again.',
  'cancelled' || 'canceled' => 'That was stopped before it finished. Nothing was changed.',
  'resource-exhausted' || 'quota-exceeded' || 'too-many-requests' =>
    'Pillr is busy right now. Wait a minute and try again.',
  'invalid-argument' => "Something in what you entered isn't right. Check it and try again.",
  'failed-precondition' =>
    "That can't be done yet. Something else needs doing first. Refresh the page and try again.",
  'unimplemented' => "That isn't available in this version of Pillr yet.",
  'invalid-checksum' || 'data-loss' => 'The file got damaged on the way. Try uploading it again.',
  'wrong-password' || 'invalid-credential' || 'user-not-found' || 'invalid-login-credentials' =>
    "That email and password don't match. Check them and try again.",
  'invalid-email' => "That doesn't look like an email address. Check it and try again.",
  'user-disabled' => 'This account has been turned off. Ask your church admin.',
  'email-already-in-use' => 'Someone already uses that email on Pillr. Sign in instead.',
  'weak-password' => 'Choose a longer password, at least 8 characters.',
  _ => _generic,
};

/// Whether a message reads like a sentence written for people rather than a
/// code, a class name or a dump.
bool _isOurs(String m) {
  if (m.isEmpty || m.length > 220) return false;
  if (RegExp(r'\[[a-z_]+/[a-z-]+\]').hasMatch(m)) return false;
  if (RegExp(r'(Exception|Error|Null check|NoSuchMethod|Instance of|TypeError|RangeError|'
          r'Bad state|Invalid argument|Unsupported operation|Unhandled|LateInitialization|'
          r'is not a subtype|Assertion failed|'
          r'_[A-Z]\w+|#\d+\s|\.dart|http[s]?://|\{|\}|INTERNAL|PERMISSION_DENIED)')
      .hasMatch(m)) {
    return false;
  }
  return RegExp(r'[A-Za-z]{3,}\s+[A-Za-z]').hasMatch(m);
}
