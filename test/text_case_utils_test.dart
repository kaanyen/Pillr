import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/core/utils/text_case_utils.dart';

void main() {
  group('TextCaseUtils.toTitleCase', () {
    test('title-cases all-caps multi-word names', () {
      expect(
        TextCaseUtils.toTitleCase('ELIKPLIM BARRIGAH ANDREW'),
        'Elikplim Barrigah Andrew',
      );
    });

    test('preserves short all-caps letter codes (2–4 chars)', () {
      expect(TextCaseUtils.toTitleCase('FC'), 'FC');
      expect(TextCaseUtils.toTitleCase('USA'), 'USA');
    });

    test('title-cases longer all-caps fellowship names', () {
      expect(TextCaseUtils.toTitleCase('QADASH'), 'Qadash');
      expect(TextCaseUtils.toTitleCase('ONLINE'), 'Online');
    });

    test('is idempotent for already formatted names', () {
      expect(TextCaseUtils.toTitleCase('Marian Gasinu'), 'Marian Gasinu');
      expect(TextCaseUtils.toTitleCase('Jane'), 'Jane');
    });

    test('hyphenated segments', () {
      expect(TextCaseUtils.toTitleCase('MARY-JANE WATSON'), 'Mary-Jane Watson');
    });

    test('trims and collapses whitespace', () {
      expect(TextCaseUtils.toTitleCase('  john   smith  '), 'John Smith');
    });
  });
}
