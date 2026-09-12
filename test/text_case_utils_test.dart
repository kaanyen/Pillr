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

    test('does not turn Ghanaian day-names into acronyms', () {
      // Yaw, Ama, Kofi, Akua, Kojo, Yaa, Esi and Afia are three and four
      // letters. An all-caps spreadsheet used to leave them shouting.
      expect(TextCaseUtils.toTitleCase('YAW DARKO'), 'Yaw Darko');
      expect(TextCaseUtils.toTitleCase('AMA SERWAA'), 'Ama Serwaa');
      expect(TextCaseUtils.toTitleCase('KOFI MENSAH'), 'Kofi Mensah');
      expect(TextCaseUtils.toTitleCase('AKUA BOATENG'), 'Akua Boateng');
      expect(TextCaseUtils.toTitleCase('YAA ASANTEWAA'), 'Yaa Asantewaa');
      expect(TextCaseUtils.toTitleCase('JOHN MENSAH'), 'John Mensah');
      // This one was already right, which is what made the bug hard to see.
      expect(TextCaseUtils.toTitleCase('KWAME NKRUMAH'), 'Kwame Nkrumah');
    });

    test('a bare code is still left alone', () {
      expect(TextCaseUtils.toTitleCase('FC'), 'FC');
      expect(TextCaseUtils.toTitleCase('USA'), 'USA');
      expect(TextCaseUtils.toTitleCase('  FC  '), 'FC');
    });
  });
}
