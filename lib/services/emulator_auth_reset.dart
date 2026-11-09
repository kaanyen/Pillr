/// Forgets any saved sign-in before Firebase starts, for emulator builds.
///
/// On web, `Firebase.initializeApp` creates Auth with saved sessions switched
/// on and immediately checks the saved user with Google — before the app gets
/// a chance to point Auth at the emulator. A reload after signing in to the
/// emulator therefore sent that user's token to the live project's
/// `accounts:lookup`. With nothing saved there is nothing to check, so the
/// first network call Auth makes is the sign-in, by which time it is wired to
/// the emulator. Emulator sessions no longer survive a reload; that is the
/// price, and it is the right way round.
library;

export 'emulator_auth_reset_stub.dart'
    if (dart.library.html) 'emulator_auth_reset_web.dart';
