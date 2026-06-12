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
