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

  /// Whether [currencyCode] has a rate the church actually set.
  ///
  /// [rateFor] falls back to 1.0 so a conversion always produces a number, but
  /// for a foreign currency that fallback is a lie: it records a $100 gift as
  /// ₵100. Callers offering a currency the church has not configured must ask
  /// this first and refuse, rather than bank the fallback.
  bool hasRateFor(String currencyCode) {
    final code = currencyCode.toUpperCase();
    if (code == BaseCurrency.code) return true;
    return ratesToBase.containsKey(code);
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
      // Rounded to the pesewa, because that is the smallest amount that can be
      // banked and the smallest the aggregate trigger will count: it sums
      // `round(amountCedis * 100)`. An entry holding 416.625 is counted as
      // 416.63 in the partner's total and as 416.625 by the totals audit's
      // recount, which reads as drift the repair tool can never settle.
      amountBase: _toPesewa(sourceAmount * rate),
      rateAvailable: hasRateFor(code),
    );
  }
}

double _toPesewa(double cedis) => (cedis * 100).round() / 100;

/// Result of converting an entered amount to the church base currency (GHS).
class CurrencyConversion {
  const CurrencyConversion({
    required this.sourceCurrency,
    required this.sourceAmount,
    required this.exchangeRateToBase,
    required this.amountBase,
    this.rateAvailable = true,
  });

  final String sourceCurrency;
  final double sourceAmount;
  final double exchangeRateToBase;
  final double amountBase;

  /// False when the church has set no rate for [sourceCurrency] and the
  /// conversion fell back to 1:1. The amount is then not a conversion at all,
  /// and must not be recorded as one.
  final bool rateAvailable;

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
