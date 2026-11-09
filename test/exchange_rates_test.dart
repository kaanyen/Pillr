import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/church/domain/exchange_rates.dart';

void main() {
  test('convert foreign amount to GHS base', () {
    const rates = ChurchExchangeRates(
      ratesToBase: {
        SelectableCurrency.usd: 12.5,
        SelectableCurrency.eur: 13.0,
        SelectableCurrency.gbp: 16.0,
      },
    );

    final usd = rates.convert(sourceAmount: 100, sourceCurrency: 'USD');
    expect(usd.amountBase, 1250);
    expect(usd.exchangeRateToBase, 12.5);

    final ghs = rates.convert(sourceAmount: 500, sourceCurrency: 'GHS');
    expect(ghs.amountBase, 500);
    expect(ghs.exchangeRateToBase, 1.0);
  });

  test('parseCurrencyCode understands common labels', () {
    expect(parseCurrencyCode('USD'), SelectableCurrency.usd);
    expect(parseCurrencyCode('Pounds'), SelectableCurrency.gbp);
    expect(parseCurrencyCode('Euro'), SelectableCurrency.eur);
    expect(parseCurrencyCode('GHS'), BaseCurrency.code);
    expect(parseCurrencyCode(null), isNull);
  });

  test('fromSettings reads nested exchangeRates map', () {
    final rates = ChurchExchangeRates.fromSettings({
      'exchangeRates': {'USD': 12.5, 'EUR': 13, 'GBP': 16},
    });
    expect(rates.rateFor('USD'), 12.5);
    expect(rates.rateFor('EUR'), 13);
    expect(rates.rateFor('GBP'), 16);
  });

  test('parseAmountCell detects currency symbols', () {
    expect(parseAmountCell(r'$400').amount, 400);
    expect(parseAmountCell(r'$400').currency, SelectableCurrency.usd);
    expect(parseAmountCell('€500').amount, 500);
    expect(parseAmountCell('€500').currency, SelectableCurrency.eur);
    expect(parseAmountCell('£1,200').amount, 1200);
    expect(parseAmountCell('£1,200').currency, SelectableCurrency.gbp);
    expect(parseAmountCell('C300').amount, 300);
    expect(parseAmountCell('C300').currency, isNull);
    expect(parseAmountCell('500').currency, isNull);
  });
}
