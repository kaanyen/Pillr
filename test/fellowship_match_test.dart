import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/fellowships/fellowship_match.dart';

void main() {
  test('mergeKnownFellowships title-cases and drops duplicates', () {
    expect(
      mergeKnownFellowships(
        const ['fire fellowship', 'Campus A'],
        const ['Fire Fellowship', 'bethel', ''],
      ),
      ['Bethel', 'Campus A', 'Fire Fellowship'],
    );
  });

  test('fellowshipNamesMatch ignores case and trim', () {
    expect(fellowshipNamesMatch(' Fire ', 'fire'), isTrue);
    expect(fellowshipNamesMatch('Fire', 'Bethel'), isFalse);
  });

  test('suggestSimilarFellowship prefers an exact name', () {
    expect(
      suggestSimilarFellowship('fire fellowship', const [
        'Bethel',
        'Fire Fellowship',
      ]),
      'Fire Fellowship',
    );
  });

  test('suggestSimilarFellowship finds a close misspelling', () {
    expect(
      suggestSimilarFellowship('Fire Felowship', const [
        'Bethel',
        'Fire Fellowship',
        'Online',
      ]),
      'Fire Fellowship',
    );
  });

  test('suggestSimilarFellowship uses lone containment', () {
    expect(
      suggestSimilarFellowship('Fire', const ['Fire Fellowship', 'Bethel']),
      'Fire Fellowship',
    );
  });

  test('suggestSimilarFellowship stays quiet when nothing is close', () {
    expect(
      suggestSimilarFellowship('Campus A', const ['Bethel', 'Zion']),
      isNull,
    );
  });
}
