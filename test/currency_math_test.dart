import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/core/utils/money.dart';
import 'package:the_pillr/features/church/domain/exchange_rates.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/maintenance/domain/totals_audit.dart';

/// Money the app stores has to be money the app can add up again.
///
/// Two sums have to agree for the Data health tool to be believable: the
/// running totals the Cloud Function keeps (which works in whole pesewas —
/// `toPesewas` rounds every entry) and the totals audit's recount from the
/// entries. Anything that lets an entry hold a fraction of a pesewa makes the
/// two disagree forever, and the audit reports drift that repairing cannot fix.
PartnershipEntry entry(double amount) => PartnershipEntry(
  id: 'e1',
  churchId: 'c1',
  partnerId: 'p1',
  partnerSnapshot: const {'fullName': 'Person A'},
  partnershipArmId: 'a1',
  armSnapshot: const {'name': 'Missions'},
  partnershipPeriodId: 'per1',
  periodSnapshot: const {'name': '2026'},
  amountCedis: amount,
  dateGiven: DateTime(2026, 3, 12),
  status: 'approved',
  createdBy: 'u1',
  createdBySnapshot: const {'fullName': 'Tester'},
  createdAt: DateTime(2026, 3, 12),
  updatedAt: DateTime(2026, 3, 12),
);

/// What the Cloud Function's `toPesewas` would make of the same entries.
double triggerTotalOf(Iterable<double> amounts) {
  var pesewas = 0;
  for (final a in amounts) {
    pesewas += (a * 100).round();
  }
  return pesewas / 100;
}

void main() {
  const rates = ChurchExchangeRates(
    ratesToBase: {SelectableCurrency.usd: 12.5, SelectableCurrency.gbp: 16.0},
  );

  group('a converted amount is money, not a fraction of a pesewa', () {
    test('an odd foreign amount converts to a whole number of pesewas', () {
      final c = rates.convert(sourceAmount: 33.33, sourceCurrency: 'USD');
      // 33.33 x 12.5 = 416.625 — six-tenths of a pesewa cannot be banked.
      expect(c.amountBase, 416.63);
      expect((c.amountBase * 100) % 1, 0, reason: 'must be whole pesewas');
    });

    test('the audit and the trigger reach the same figure', () {
      final amounts = [
        rates.convert(sourceAmount: 33.33, sourceCurrency: 'USD').amountBase,
        rates.convert(sourceAmount: 12.07, sourceCurrency: 'GBP').amountBase,
        rates.convert(sourceAmount: 5.55, sourceCurrency: 'USD').amountBase,
      ];
      final audit = expectedTotalsBy([
        for (final a in amounts) entry(a),
      ], (e) => e.partnerId).amountFor('p1');

      expect(
        audit,
        triggerTotalOf(amounts),
        reason: 'a phantom drift the repair tool cannot settle',
      );
    });

    test('the base currency is left exactly as entered', () {
      final c = rates.convert(sourceAmount: 1000.55, sourceCurrency: 'GHS');
      expect(c.amountBase, 1000.55);
      expect(c.exchangeRateToBase, 1.0);
    });
  });

  group('a currency with no configured rate', () {
    test('is reported as unconfigured rather than treated as 1:1', () {
      expect(rates.hasRateFor('USD'), isTrue);
      expect(
        rates.hasRateFor('GHS'),
        isTrue,
        reason: 'the base is always known',
      );
      expect(rates.hasRateFor('EUR'), isFalse);
    });

    test('does not silently record a euro as a cedi', () {
      final c = rates.convert(sourceAmount: 100, sourceCurrency: 'EUR');
      expect(c.rateAvailable, isFalse);
      expect(
        c.amountBase,
        100,
        reason: 'the figure is unchanged, but the caller must be told why',
      );
    });
  });

  moneyTests();
}

/// Totals are kept as whole pesewas so they can be added and taken away again
/// without residue. Documents written before that field existed carry only the
/// cedi figure, and must still read correctly.
void moneyTests() {
  group('a stored total is read at pesewa precision', () {
    test('prefers the exact field when the document has one', () {
      final read = storedTotalCedis(
        {
          'totalApprovedPesewas': 100010000,
          'totalApprovedAmount': 1000099.9999,
        },
        pesewasKey: 'totalApprovedPesewas',
        cedisKey: 'totalApprovedAmount',
      );
      expect(read, 1000100.0);
    });

    test('falls back to the cedi field on a document that predates it', () {
      final read = storedTotalCedis(
        {'totalApprovedAmount': 1000100.0},
        pesewasKey: 'totalApprovedPesewas',
        cedisKey: 'totalApprovedAmount',
      );
      expect(read, 1000100.0);
    });

    test('a missing total reads as nothing, not as null', () {
      final read = storedTotalCedis(
        const {},
        pesewasKey: 'totalApprovedPesewas',
        cedisKey: 'totalApprovedAmount',
      );
      expect(read, 0);
    });

    test(
      'adding and removing the same giving in pesewas leaves exactly zero',
      () {
        // The same round trip in cedi doubles leaves ~2.3e-13 behind.
        final amounts = [33.33, 33.33, 33.34, 0.01, 1234.57, 0.1, 0.2];
        var pesewas = 0;
        for (final a in amounts) {
          pesewas += toPesewas(a);
        }
        for (final a in amounts) {
          pesewas -= toPesewas(a);
        }
        expect(pesewas, 0);
        expect(fromPesewas(pesewas), 0.0);

        var cedis = 0.0;
        for (final a in amounts) {
          cedis += a;
        }
        for (final a in amounts) {
          cedis -= a;
        }
        expect(cedis, isNot(0.0), reason: 'this is the drift being avoided');
      },
    );
  });

  group('the audit compares whole pesewas', () {
    test('a total that is off by one pesewa is drift', () {
      final drift = findTotalsDrift(
        kind: TotalsDriftKind.partner,
        stored: [
          const StoredTotal(
            id: 'p1',
            name: 'Person A',
            totalApprovedAmount: 100.01,
            entryCount: 1,
          ),
        ],
        expected: expectedTotalsBy([entry(100.00)], (e) => e.partnerId),
      );
      expect(drift.single.amountDelta, closeTo(-0.01, 1e-9));
    });

    test('floating-point residue is not drift', () {
      final residue = 0.1 + 0.2 - 0.3; // 5.55e-17
      final drift = findTotalsDrift(
        kind: TotalsDriftKind.partner,
        stored: [
          StoredTotal(
            id: 'p1',
            name: 'Person A',
            totalApprovedAmount: 100 + residue,
            entryCount: 1,
          ),
        ],
        expected: expectedTotalsBy([entry(100)], (e) => e.partnerId),
      );
      expect(drift, isEmpty);
    });
  });

  group('parseAmountInput', () {
    test('accepts a plain figure', () {
      expect(parseAmountInput('1200'), 1200);
    });

    test('accepts a thousands comma', () {
      expect(parseAmountInput('1,200'), 1200);
      expect(parseAmountInput('1,200.50'), 1200.50);
    });

    test('accepts spaces, symbols, and a trailing point', () {
      expect(parseAmountInput('1 200'), 1200);
      expect(parseAmountInput('₵1,200.50'), 1200.50);
      expect(parseAmountInput(' 1200. '), 1200);
    });

    test('rejects empty or non-positive input', () {
      expect(parseAmountInput(''), isNull);
      expect(parseAmountInput('   '), isNull);
      expect(parseAmountInput('0'), isNull);
      expect(parseAmountInput('abc'), isNull);
    });
  });
}
