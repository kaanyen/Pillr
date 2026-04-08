import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocalePref = 'pillr_locale';

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    Future.microtask(_hydrate);
    return null;
  }

  Future<void> _hydrate() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString(_kLocalePref);
    if (c == 'fr') {
      state = const Locale('fr');
    } else if (c == 'en') {
      state = const Locale('en');
    }
  }

  Future<void> setLocale(Locale? locale) async {
    final p = await SharedPreferences.getInstance();
    if (locale == null) {
      await p.remove(_kLocalePref);
    } else {
      await p.setString(_kLocalePref, locale.languageCode);
    }
    state = locale;
  }
}
