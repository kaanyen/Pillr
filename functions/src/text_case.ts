/**
 * Matches Dart [TextCaseUtils.toTitleCase] for names and labels.
 *
 * A value that is entirely one short all-caps token (FC, USA) keeps its
 * capitals. That exemption is deliberately not applied inside a multi-word
 * value: Ghanaian day-names are three and four letters, so an all-caps
 * spreadsheet used to leave "YAW DARKO" as "YAW Darko" and "KOFI MENSAH" as
 * "KOFI Mensah". A person's name is never an acronym.
 *
 * Keep this in step with lib/core/utils/text_case_utils.dart.
 */
export function toTitleCase(input: string): string {
  const s = input.trim();
  if (!s) return "";
  const words = s.split(/\s+/);
  if (words.length === 1 && looksLikeCode(words[0])) return words[0];
  return words.map(titleCaseWord).join(" ");
}

function looksLikeCode(word: string): boolean {
  return /^[A-Za-z]+$/.test(word) &&
    word.length >= 2 &&
    word.length <= 4 &&
    word === word.toUpperCase();
}

function titleCaseWord(word: string): string {
  if (!word) return "";
  if (word.includes("-")) return word.split("-").map(titleCaseSegment).join("-");
  if (word.includes("'")) return word.split("'").map(titleCaseSegment).join("'");
  return titleCaseSegment(word);
}

function titleCaseSegment(segment: string): string {
  if (!segment) return "";
  if (/^\d/.test(segment)) return segment;
  if (segment.length === 1) return segment.toUpperCase();
  return segment[0].toUpperCase() + segment.slice(1).toLowerCase();
}
