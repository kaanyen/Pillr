/// Column mapping for partnership bulk import spreadsheets.
///
/// **Reference:** `PARTNERSHIP SAMPLE.xlsx` at the repository root (gitignored) uses a
/// title block in rows 1–2; **headers are on Excel row 5** (data from row 6). Columns A–I:
///
/// | Col | Header (sample) | Maps to |
/// |-----|------------------|---------|
/// | A | DATE | [BulkImportColumn.date] — Excel serial or ISO-like string |
/// | B | NAME | [BulkImportColumn.name] |
/// | C | CONTACT | [BulkImportColumn.contact] — phone |
/// | D | FELLOWSHIP | [BulkImportColumn.fellowship] |
/// | E | EMAIL | [BulkImportColumn.email] |
/// | F | AMOUNT (GHC) | [BulkImportColumn.amount] |
/// | G | CATEGORY (eg. Church service, Programs, Rhapsody etc) | [BulkImportColumn.category] — partnership arm (name). Extra text is OK: the importer matches configured arm names loosely (comma/slash segments, substring, longest match). |
/// | H | TO WHOM GIVEN TO DIRECTLY | [BulkImportColumn.givenToNotes] — merged into entry notes |
/// | I | CURRENTLY WITH PASTOR (YES OR NO) | [BulkImportColumn.pastorConfirmed] |
///
/// There is **no period column** in the sample; the app uses the **active** [PartnershipPeriod]
/// from church settings at import time.
///
/// **Optional:** `MEMBER ID` / `MEMBER_ID` — when present, used to match an existing partner.
enum BulkImportColumn {
  date,
  name,
  memberId,
  contact,
  fellowship,
  email,
  amount,
  category,
  givenToNotes,
  pastorConfirmed,
}

/// Normalizes a header cell for matching: lowercase, trim, collapse inner whitespace.
String normalizeHeaderKey(String? s) {
  if (s == null) return '';
  return s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Returns the [BulkImportColumn] for a normalized header, or null if unknown.
BulkImportColumn? columnForHeader(String normalizedHeader) {
  final h = normalizeHeaderKey(normalizedHeader);
  if (h.isEmpty) return null;

  const dateKeys = {'date', 'date given'};
  if (dateKeys.contains(h)) return BulkImportColumn.date;

  if (h == 'name' || h == 'full name' || h == 'partner name') {
    return BulkImportColumn.name;
  }

  if (h == 'member id' || h == 'memberid' || h == 'member_id') {
    return BulkImportColumn.memberId;
  }

  if (h == 'contact' || h == 'phone' || h == 'mobile' || h == 'telephone') {
    return BulkImportColumn.contact;
  }

  if (h == 'fellowship') return BulkImportColumn.fellowship;

  if (h == 'email' || h == 'e-mail') return BulkImportColumn.email;

  if (h.contains('amount') && (h.contains('ghc') || h.contains('cedis') || h.endsWith('amount'))) {
    return BulkImportColumn.amount;
  }
  if (h == 'amount' || h == 'amount (ghc)') return BulkImportColumn.amount;

  if (h.startsWith('category') || h.contains('church service') && h.contains('category')) {
    return BulkImportColumn.category;
  }
  if (h == 'arm' || h == 'partnership arm') return BulkImportColumn.category;

  if (h.contains('to whom given') || h == 'given to' || h == 'notes') {
    return BulkImportColumn.givenToNotes;
  }

  if (h.contains('currently with pastor') || h.contains('pastor') && h.contains('yes')) {
    return BulkImportColumn.pastorConfirmed;
  }
  if (h == 'pastor confirmed' || h == 'confirmed') return BulkImportColumn.pastorConfirmed;

  return null;
}
