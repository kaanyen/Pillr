/// Money, kept in the smallest unit that exists.
///
/// A cedi amount in a double is fine to show and hopeless to accumulate: no
/// binary double holds 0.10 exactly, so a total that has had a few hundred
/// entries of giving added and taken away again lands near zero rather than on it. The
/// aggregate trigger therefore keeps running totals as a whole number of
/// pesewas and moves them by whole numbers, which is exact whatever order the
/// moves arrive in.
///
/// Documents written before that field existed only carry the cedi figure, so
/// every read goes through [storedTotalCedis], which prefers the exact field
/// and falls back to the old one. Backfilling happens through the totals-audit
/// repair in Tools; nothing here rewrites data on its own.
library;

/// The pesewa count an amount in cedis stands for.
///
/// Rounds, because a fraction of a pesewa is not money — and rounds the same
/// way as `toPesewas` in `functions/src/index.ts`, which is what makes the
/// app's recount and the trigger's running total agree.
int toPesewas(num cedis) => (cedis * 100).round();

/// Cedis from a whole number of pesewas.
double fromPesewas(int pesewas) => pesewas / 100;

/// The number someone meant, even if they typed it the way a person types money.
///
/// Accepts `1200`, `1,200`, `1 200`, `₵1,200.50`, and a trailing decimal
/// point. Returns null when there is no positive amount in the string.
double? parseAmountInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  var numeric = trimmed
      .replaceAll(RegExp(r'[A-Za-z₵€£$\s]'), '')
      .replaceAll(',', '');
  numeric = numeric.replaceAll(RegExp(r'\.$'), '');
  final value = double.tryParse(numeric);
  if (value == null || value <= 0) return null;
  return value;
}

/// Reads a stored total, preferring the exact pesewa field when the document
/// has one.
double storedTotalCedis(
  Map<String, dynamic> data, {
  required String pesewasKey,
  required String cedisKey,
}) {
  final exact = data[pesewasKey];
  if (exact is num) return fromPesewas(exact.round());
  return (data[cedisKey] as num?)?.toDouble() ?? 0;
}
