import '../../features/entries/domain/partnership_entry.dart';
import 'pdf_branding.dart';

/// One row in the giving report table.
class PartnerGivingRecord {
  const PartnerGivingRecord({
    required this.partnerName,
    required this.armCategory,
    required this.status,
    required this.dateGiven,
    required this.amount,
  });

  final String partnerName;
  final String armCategory;
  final String status;
  final String dateGiven;
  final double amount;
}

/// Subtotal for one partnership arm category.
class ArmSummary {
  const ArmSummary({
    required this.armCategory,
    required this.subtotalAmount,
  });

  final String armCategory;
  final double subtotalAmount;
}

/// Data injected into the landscape Pillr Records PDF template.
class GivingLedgerReportData {
  const GivingLedgerReportData({
    required this.organizationName,
    required this.scopeLine,
    required this.scopeHighlight,
    required this.totalGivingsAmount,
    required this.armSummaries,
    required this.records,
    required this.generatedAtFormatted,
    required this.exporterName,
    required this.verificationId,
    this.currencySymbol = 'GHS',
  });

  final String organizationName;
  /// Human-readable scope, e.g. "Approved giving · Missions · August 2026".
  final String scopeLine;
  /// Short segment highlighted in cyan, usually the period or month.
  final String scopeHighlight;
  final double totalGivingsAmount;
  final List<ArmSummary> armSummaries;
  final List<PartnerGivingRecord> records;
  final String generatedAtFormatted;
  final String exporterName;
  final String verificationId;
  final String currencySymbol;
}

/// Maps export entries into [GivingLedgerReportData].
abstract final class GivingLedgerReportBuilder {
  static GivingLedgerReportData fromEntries({
    required List<PartnershipEntry> entries,
    required String organizationName,
    required String generatedAtFormatted,
    required String exporterName,
    String? periodScope,
    String? filterDescription,
    String? reportTitle,
    String currencySymbol = 'GHS',
    DateTime? verificationSeed,
    String? Function(PartnershipEntry entry)? armNameOf,
  }) {
    // The ledger shows main arms only: giving recorded to a sub-arm is listed
    // and subtotalled under its main arm. [armNameOf] maps an entry to that
    // name; without it the name stored on the entry is used.
    String armOf(PartnershipEntry e) =>
        armNameOf?.call(e) ?? e.armSnapshot['name']?.toString() ?? '';
    final records = [
      for (final e in entries)
        PartnerGivingRecord(
          partnerName: pdfSafeText(e.partnerSnapshot['fullName']?.toString()),
          armCategory: pdfSafeText(armOf(e)),
          status: e.status,
          dateGiven: pdfFormatDate(e.dateGiven),
          amount: e.amountCedis,
        ),
    ]..sort((a, b) {
        final byDate = b.dateGiven.compareTo(a.dateGiven);
        if (byDate != 0) return byDate;
        return a.partnerName.compareTo(b.partnerName);
      });

    final armTotals = <String, double>{};
    for (final row in records) {
      armTotals[row.armCategory] =
          (armTotals[row.armCategory] ?? 0) + row.amount;
    }
    final armSummaries = armTotals.entries
        .map(
          (e) => ArmSummary(armCategory: e.key, subtotalAmount: e.value),
        )
        .toList()
      ..sort((a, b) => b.subtotalAmount.compareTo(a.subtotalAmount));

    final total = records.fold<double>(0, (sum, r) => sum + r.amount);
    final highlight = _resolveHighlight(entries, periodScope);
    final seed = verificationSeed ?? DateTime.now();

    return GivingLedgerReportData(
      organizationName: organizationName,
      scopeLine: buildScopeLine(
        entries: entries,
        periodScope: periodScope,
        filterDescription: filterDescription,
        reportTitle: reportTitle,
      ),
      scopeHighlight: highlight,
      totalGivingsAmount: total,
      armSummaries: armSummaries,
      records: records,
      generatedAtFormatted: pdfSafeText(generatedAtFormatted),
      exporterName: pdfSafeText(exporterName),
      verificationId: verificationId(seed),
      currencySymbol: currencySymbol.toUpperCase(),
    );
  }

  static String buildScopeLine({
    required List<PartnershipEntry> entries,
    String? periodScope,
    String? filterDescription,
    String? reportTitle,
  }) {
    final parts = <String>[];

    if (filterDescription != null && filterDescription.trim().isNotEmpty) {
      final cleaned = filterDescription
          .replaceAll(RegExp(r'\s*[—–-]\s*\d+\s+entries\s*$'), '')
          .trim();
      final segments = _meaningfulFilterSegments(cleaned);
      if (segments.isNotEmpty) {
        parts.add(_formatFilterSegments(segments, entries));
      }
    }

    if (parts.isEmpty) {
      final label = _statusGivingLabel(entries);
      if (label != 'Giving') parts.add(label);
    }

    final period = periodScope?.trim();
    if (period != null && period.isNotEmpty) {
      parts.add(period);
    }

    final filterText = parts.join(' ').toLowerCase();
    final arms = entries
        .map((e) => e.armSnapshot['name']?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    if (arms.length == 1 && !filterText.contains(arms.first.toLowerCase())) {
      parts.add('${arms.first} arm');
    }

    final fellowships = entries
        .map((e) => e.partnerSnapshot['fellowship']?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    if (fellowships.length == 1 &&
        !filterText.contains(fellowships.first.toLowerCase())) {
      parts.add('${fellowships.first} fellowship');
    }

    final monthLabel = _sharedMonthLabel(entries);
    if (monthLabel != null && !filterText.contains(monthLabel.toLowerCase())) {
      parts.add(monthLabel);
    }

    final title = reportTitle?.trim();
    if (title != null &&
        title.isNotEmpty &&
        title != 'Records' &&
        title != 'Queue' &&
        !filterText.contains(title.toLowerCase())) {
      parts.add(title);
    }

    if (parts.isEmpty) return 'Giving';
    return parts.join(' · ');
  }

  static List<String> _meaningfulFilterSegments(String cleaned) {
    return cleaned
        .split(' · ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .where((s) => s.toLowerCase() != 'all statuses')
        .toList();
  }

  static String _formatFilterSegments(
    List<String> segments,
    List<PartnershipEntry> entries,
  ) {
    final armNames = entries
        .map((e) => e.armSnapshot['name']?.toString().trim().toLowerCase() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    final formatted = segments.map((segment) {
      if (armNames.contains(segment.toLowerCase())) return '$segment arm';
      return _normalizeGivingPhrase(segment);
    });
    return formatted.join(' · ');
  }

  static String verificationId(DateTime at) {
    final tail = (at.millisecondsSinceEpoch % 9000 + 1000).toString();
    return 'PLR-${at.year}-$tail';
  }

  static String _normalizeGivingPhrase(String value) {
    var text = value;
    text = text.replaceAll(RegExp(r'\bledger\b', caseSensitive: false), 'giving');
    text = text.replaceAll(
      RegExp(r'\bcontributions?\b', caseSensitive: false),
      'giving',
    );
    text = text.replaceAll(RegExp(r'\bgifts?\b', caseSensitive: false), 'giving');
    if (!text.toLowerCase().contains('giving')) {
      text = '$text giving';
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _statusGivingLabel(List<PartnershipEntry> entries) {
    final statuses = entries.map((e) => e.status).where((s) => s.isNotEmpty).toSet();
    if (statuses.length == 1) {
      final status = statuses.first;
      return '${status[0].toUpperCase()}${status.substring(1)} giving';
    }
    return 'Giving';
  }

  static String? _sharedMonthLabel(List<PartnershipEntry> entries) {
    if (entries.isEmpty) return null;
    final months = entries
        .map((e) => '${e.dateGiven.year}-${e.dateGiven.month.toString().padLeft(2, '0')}')
        .toSet();
    if (months.length != 1) return null;
    final sample = entries.first.dateGiven;
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${monthNames[sample.month - 1]} ${sample.year}';
  }

  static String _resolveHighlight(
    List<PartnershipEntry> entries,
    String? periodScope,
  ) {
    final period = periodScope?.trim();
    if (period != null && period.isNotEmpty) return period;
    final month = _sharedMonthLabel(entries);
    if (month != null) return month;
    final names = entries
        .map((e) => e.periodSnapshot['name']?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    if (names.length == 1) return names.first;
    if (entries.isEmpty) return '${DateTime.now().year}';
    final years = entries.map((e) => e.dateGiven.year).toSet();
    if (years.length == 1) return '${years.first}';
    return '${DateTime.now().year}';
  }
}
