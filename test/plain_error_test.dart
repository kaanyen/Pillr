import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/core/errors/app_exception.dart';
import 'package:the_pillr/core/errors/plain_error.dart';

void main() {
  test('the logo upload error becomes a plain sentence', () {
    final m = plainErrorText('[firebase_storage/unauthorized] User is not authorized to perform the desired action.');
    expect(m, startsWith("Pillr didn't let you do that."));
    expect(m, isNot(contains('firebase')));
  });

  test('platform errors never show codes or class names', () {
    for (final e in <Object>[
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'The service is currently unavailable.'),
      FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'),
      FirebaseFunctionsException(code: 'internal', message: 'INTERNAL'),
      StateError('Bad state: No element'),
      Exception('Null check operator used on a null value'),
    ]) {
      final m = plainError(e);
      expect(m, isNot(matches(RegExp(r'firebase|INTERNAL|Bad state|Null check|Exception', caseSensitive: false))), reason: '$e → $m');
    }
  });

  test("Pillr's own server sentences are kept", () {
    final e = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'A backup started less than an hour ago. Try again later.',
    );
    expect(plainError(e), 'A backup started less than an hour ago. Try again later.');
    expect(plainError(AppException('Turn on monthly partner emails first.')), 'Turn on monthly partner emails first.');
  });

  test('no connection reads as no connection', () {
    expect(plainErrorText('SocketException: Failed host lookup'), contains("can't be reached"));
    expect(plainError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')), contains("can't be reached"));
  });
}
