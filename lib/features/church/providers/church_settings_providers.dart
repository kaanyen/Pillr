import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/church_settings_repository.dart';
import '../domain/church_settings.dart';

String _localeForCurrency(String code) {
  switch (code.toUpperCase()) {
    case 'GHS':
      return 'en_GH';
    case 'GBP':
      return 'en_GB';
    case 'EUR':
      return 'de_DE';
    default:
      return 'en_US';
  }
}

String _fallbackSymbol(String code) {
  switch (code.toUpperCase()) {
    case 'GHS':
      return '\u20B5';
    case 'USD':
      return r'$';
    case 'EUR':
      return '\u20AC';
    case 'GBP':
      return '\u00A3';
    default:
      return code;
  }
}

final churchSettingsRepositoryProvider = Provider<ChurchSettingsRepository>((ref) {
  return ChurchSettingsRepository(ref.watch(firestoreProvider));
});

final churchSettingsProvider = StreamProvider<ChurchSettings?>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value(null);
  return ref.watch(churchSettingsRepositoryProvider).watchChurch(idx.churchId);
});

/// Church display name (convenience for UI).
final churchNameProvider = Provider<String?>((ref) {
  return ref.watch(churchSettingsProvider).valueOrNull?.name;
});

/// Money formatter from the church document (`currency` / `currencySymbol`).
final churchMoneyFormatProvider = Provider<String Function(num)>((ref) {
  final settings = ref.watch(churchSettingsProvider).valueOrNull;
  final code = (settings?.currency ?? 'GHS').toUpperCase();
  final symRaw = settings?.currencySymbol?.trim();
  final symbol =
      (symRaw != null && symRaw.isNotEmpty) ? symRaw : _fallbackSymbol(code);
  final fmt = NumberFormat.currency(
    locale: _localeForCurrency(code),
    symbol: symbol,
    decimalDigits: 2,
  );
  return (n) => fmt.format(n);
});

/// Money shortened to fit a stat tile: ₵11.1B rather than ₵11,101,126,000.50.
///
/// A figure that runs off the end of its card and ellipsises is worse than a
/// rounded one — you cannot read either the total or the magnitude. The exact
/// amount stays available on hover.
final churchCompactMoneyProvider = Provider<String Function(num)>((ref) {
  final settings = ref.watch(churchSettingsProvider).valueOrNull;
  final code = (settings?.currency ?? 'GHS').toUpperCase();
  final symRaw = settings?.currencySymbol?.trim();
  final symbol =
      (symRaw != null && symRaw.isNotEmpty) ? symRaw : _fallbackSymbol(code);
  final exact = ref.watch(churchMoneyFormatProvider);

  return (n) {
    final v = n.toDouble().abs();
    // Under a hundred thousand the full figure fits, and the pesewas matter.
    if (v < 100000) return exact(n);
    final sign = n < 0 ? '-' : '';
    final (double scaled, String suffix) = switch (v) {
      >= 1000000000000 => (v / 1000000000000, 'T'),
      >= 1000000000 => (v / 1000000000, 'B'),
      >= 1000000 => (v / 1000000, 'M'),
      _ => (v / 1000, 'K'),
    };
    // One decimal up to 100, none above — 11.1B, but 340B not 340.2B.
    final text = scaled >= 100
        ? scaled.round().toString()
        : scaled.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '$sign$symbol$text$suffix';
  };
});
