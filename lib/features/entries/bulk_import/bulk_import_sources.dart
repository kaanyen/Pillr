/// Alternative ways to get a grid into the importer.
///
/// Everything the importer understands is a `List<List<String?>>` — the same
/// shape [readFirstXlsxSheet] produces. Adding an input path therefore means
/// producing that grid; the parser, resolver and review flow are untouched.
library;

/// Splits delimited text into a grid.
///
/// Handles the quoting rules real spreadsheets emit: a field wrapped in double
/// quotes may contain the delimiter, newlines, and doubled `""` for a literal
/// quote. Rows may end with `\n` or `\r\n`.
List<List<String?>> parseDelimitedGrid(String text, {required String delimiter}) {
  final rows = <List<String?>>[];
  var row = <String?>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldWasQuoted = false;

  void endField() {
    final raw = field.toString();
    // An unquoted empty field is a genuinely empty cell; a quoted one is an
    // empty string the author typed on purpose. Both read as empty here, but
    // trimming only the unquoted case preserves deliberate padding.
    row.add(fieldWasQuoted ? raw : raw.trim());
    field.clear();
    fieldWasQuoted = false;
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String?>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];

    if (inQuotes) {
      if (ch == '"') {
        // A doubled quote inside a quoted field is one literal quote.
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
      continue;
    }

    if (ch == '"' && field.isEmpty) {
      inQuotes = true;
      fieldWasQuoted = true;
    } else if (ch == delimiter) {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else if (ch == '\r') {
      // Swallow; the \n that follows ends the row.
    } else {
      field.write(ch);
    }
  }

  // Trailing content with no final newline is still a row.
  if (field.isNotEmpty || row.isNotEmpty) endRow();

  // Drop trailing all-empty rows, which spreadsheets emit generously.
  while (rows.isNotEmpty && rows.last.every((c) => (c ?? '').isEmpty)) {
    rows.removeLast();
  }
  return rows;
}

/// CSV text, as exported by Excel, Google Sheets, bank portals and mobile
/// money statements.
List<List<String?>> parseCsvGrid(String text) =>
    parseDelimitedGrid(text, delimiter: ',');

/// A block of cells copied out of a spreadsheet.
///
/// Excel and Google Sheets both put **tab**-separated text on the clipboard,
/// so tab is tried first. If the text has no tabs but does have commas, it is
/// almost certainly CSV someone pasted from a text file, so fall back rather
/// than returning one column of full lines.
List<List<String?>> parsePastedGrid(String text) {
  if (text.contains('\t')) {
    return parseDelimitedGrid(text, delimiter: '\t');
  }
  if (text.contains(',')) return parseCsvGrid(text);
  return parseDelimitedGrid(text, delimiter: '\t');
}

/// True when [name] looks like something [parseCsvGrid] should handle.
bool isCsvFileName(String name) {
  final n = name.toLowerCase().trim();
  return n.endsWith('.csv') || n.endsWith('.txt');
}
