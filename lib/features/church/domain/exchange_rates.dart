/// Church base currency and foreign exchange rates to GHS.
abstract final class BaseCurrency {
  static const code = 'GHS';
  static const symbol = '\u20B5';
}

/// Currencies staff can pick when recording giving.
abstract final class SelectableCurrency {
  static const ghs = 'GHS';
  static const usd = 'USD';
  static const eur = 'EUR';
  static const gbp = 'GBP';

  static const all = [ghs, usd, eur, gbp];

  static String label(String code) => switch (code.toUpperCase()) {
        ghs => 'Ghana cedi (GHS)',
        usd => 'US dollar (USD)',
        eur => 'Euro (EUR)',
        gbp => 'British pound (GBP)',
        _ => code.toUpperCase(),
      };
}

/// Snapshot of configured rates: 1 unit of foreign currency → GHS.
class ChurchExchangeRates {
  const ChurchExchangeRates({Map<String, double>? ratesToBase})
      : ratesToBase = ratesToBase ?? const {};

  final Map<String, double> ratesToBase;

  /// Airport City Church starting rates (editable in Settings).
  static const airportCityDefaults = ChurchExchangeRates(
    ratesToBase: {
      SelectableCurrency.usd: 12.5,
      SelectableCurrency.eur: 13.0,
      SelectableCurrency.gbp: 16.0,
    },
  );

  factory ChurchExchangeRates.fromSettings(Map<String, dynamic>? settings) {
    if (settings == null) return const ChurchExchangeRates();
    final raw = settings['exchangeRates'];
    if (raw is! Map) return const ChurchExchangeRates();
    final parsed = <String, double>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().toUpperCase();
      if (key == BaseCurrency.code) continue;
      final v = entry.value;
      if (v is num && v > 0) parsed[key] = v.toDouble();
    }
    return ChurchExchangeRates(ratesToBase: parsed);
  }

  Map<String, double> toFirestoreMap() => Map.from(ratesToBase);

  double rateFor(String currencyCode) {
    final code = currencyCode.toUpperCase();
    if (code == BaseCurrency.code) return 1.0;
    return ratesToBase[code] ?? 1.0;
  }

  bool get hasForeignRates => ratesToBase.isNotEmpty;

  CurrencyConversion convert({
    required double sourceAmount,
    required String sourceCurrency,
  }) {
    final code = sourceCurrency.toUpperCase();
    final rate = rateFor(code);
    return CurrencyConversion(
      sourceCurrency: code,
      sourceAmount: sourceAmount,
      exchangeRateToBase: rate,
      amountBase: sourceAmount * rate,
    );
  }
}

/// Result of converting an entered amount to the church base currency (GHS).
class CurrencyConversion {
  const CurrencyConversion({
    required this.sourceCurrency,
    required this.sourceAmount,
    required this.exchangeRateToBase,
    required this.amountBase,
  });

  final String sourceCurrency;
  final double sourceAmount;
  final double exchangeRateToBase;
  final double amountBase;

  bool get isBaseCurrency => sourceCurrency == BaseCurrency.code;

  Map<String, dynamic> toEntryFields() => {
        'sourceCurrency': sourceCurrency,
        'sourceAmount': sourceAmount,
        'exchangeRateToBase': exchangeRateToBase,
        'amountCedis': amountBase,
      };
}

/// Parses a currency code from bulk-import cells (USD, US Dollar, $, etc.).
String? parseCurrencyCode(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final upper = t.toUpperCase();
  if (SelectableCurrency.all.contains(upper)) return upper;
  if (upper.contains('USD') || upper == r'$' || upper.contains('DOLLAR')) {
    return SelectableCurrency.usd;
  }
  if (upper.contains('EUR') || upper == '€' || upper.contains('EURO')) {
    return SelectableCurrency.eur;
  }
  if (upper.contains('GBP') ||
      upper.contains('POUND') ||
      upper == '£' ||
      upper.contains('STERLING')) {
    return SelectableCurrency.gbp;
  }
  if (upper.contains('GHS') ||
      upper.contains('GHC') ||
      upper.contains('CEDIS') ||
      upper == '₵') {
    return BaseCurrency.code;
  }
  return null;
}

/// Parses an amount cell that may include currency symbols or codes.
///
/// Returns the numeric value and an optional detected currency. When no
/// currency is embedded in the cell, [currency] is null and the caller should
/// fall back to the sheet default or a dedicated Currency column.
({double? amount, String? currency}) parseAmountCell(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return (amount: null, currency: null);

  final plain = double.tryParse(trimmed.replaceAll(',', ''));
  if (plain != null && plain > 0) {
    return (amount: plain, currency: null);
  }

  final fromText = parseCurrencyCode(trimmed);
  String? symbolCurrency;
  if (trimmed.contains(r'$')) {
    symbolCurrency = SelectableCurrency.usd;
  } else if (trimmed.contains('€')) {
    symbolCurrency = SelectableCurrency.eur;
  } else if (trimmed.contains('£')) {
    symbolCurrency = SelectableCurrency.gbp;
  } else if (trimmed.contains('₵')) {
    symbolCurrency = BaseCurrency.code;
  }

  var numeric = trimmed.replaceAll(RegExp(r'[A-Za-z₵€£$\s]'), '').replaceAll(',', '');
  numeric = numeric.replaceAll(RegExp(r'\.$'), '');
  final value = double.tryParse(numeric);
  if (value == null || value <= 0) return (amount: null, currency: null);

  return (amount: value, currency: fromText ?? symbolCurrency);
}
