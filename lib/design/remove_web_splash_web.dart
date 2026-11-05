import 'dart:js_interop';

@JS('removeSplashFromWeb')
external void _removeSplashFromWeb();

/// Calls the function web/index.html defines to take its splash away.
void removeWebSplash() {
  try {
    _removeSplashFromWeb();
  } catch (_) {
    // A page without the splash (tests, embeds) has nothing to remove.
  }
}
