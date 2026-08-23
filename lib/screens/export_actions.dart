import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/entry_export.dart';
import '../core/utils/export_naming.dart';
import '../l10n/app_localizations.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';

/// Export buttons for a list of entries.
///
/// These existed on the old entries, approvals and leaderboard screens and
/// were lost when those were replaced — the helpers in `entry_export.dart`
/// survived with nothing calling them. Centralised here so every list that
/// shows entries offers the same two exports from one place.
///
/// Exports respect whatever the caller has already filtered to: what you see
/// is what you get, which is the only behaviour that is not surprising.
class EntryExportButtons extends ConsumerStatefulWidget {
  const EntryExportButtons({
    super.key,
    required this.entries,
    required this.title,
    this.subtitle,
    this.scope,
    this.dense = true,
  });

  final List<PartnershipEntry> entries;
  final String title;

  /// Describes the current filter, so an exported PDF says what it contains.
  final String? subtitle;

  /// Narrows the filename — usually the period the export covers. Without it
  /// the name carries the report and the date alone.
  final String? scope;

  final bool dense;

  @override
  ConsumerState<EntryExportButtons> createState() => _EntryExportButtonsState();
}

class _EntryExportButtonsState extends ConsumerState<EntryExportButtons> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The period every entry in this export belongs to, when they share one.
  /// A mixed export has no period in its name rather than a misleading one.
  String? get _periodScope {
    if (widget.scope != null) return widget.scope;
    final names = widget.entries
        .map((e) => e.periodSnapshot['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    return names.length == 1 ? names.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The PDF is drawn in Helvetica, which has no ₵ — the symbol was being
    // dropped without a word, leaving a giving report full of bare numbers.
    // The code goes in the column heading instead, where it is said once and
    // cannot be mistaken.
    final currency =
        (ref.watch(churchSettingsProvider).valueOrNull?.currency ?? 'GHS')
            .toUpperCase();
    final plainMoney = NumberFormat.decimalPatternDigits(
      decimalDigits: 2,
    ).format;
    final church = ref.watch(churchNameProvider) ?? 'Church';
    final logoUrl = ref.watch(churchSettingsProvider).valueOrNull?.logoUrl;
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final empty = widget.entries.isEmpty;
    final now = DateTime.now();
    final when = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm().format(now);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SelButton(
          label: 'PDF',
          icon: LucideIcons.fileDown,
          dense: widget.dense,
          onPressed: empty || _busy
              ? null
              : () => _run(
                  () => shareEntriesPdf(
                    title: widget.title,
                    // The church's name belongs on its own report, above the
                    // description of what has been filtered to.
                    subtitle: [
                      church,
                      widget.subtitle ?? '${widget.entries.length} entries',
                    ].join(' · '),
                    entries: widget.entries,
                    columnHeaders: [
                      l10n.pdfTableHeaderPartner,
                      l10n.pdfTableHeaderAmountIn(currency),
                      l10n.pdfTableHeaderStatus,
                      l10n.pdfTableHeaderPeriod,
                      l10n.pdfTableHeaderArm,
                      l10n.pdfTableHeaderDateGiven,
                    ],
                    formatAmount: plainMoney,
                    logoUrl: logoUrl,
                    generatedAtLine: l10n.pdfGeneratedAt(when),
                    exporterLine: profile == null
                        ? null
                        : l10n.pdfExporter(profile.fullName),
                    footerBrand: l10n.pdfFooterBrand,
                    filename: pillrExportFileName(
                      report: widget.title,
                      scope: _periodScope,
                      on: now,
                      extension: 'pdf',
                    ),
                  ),
                ),
        ),
        const SizedBox(width: SelSpace.x2),
        SelButton(
          label: 'CSV',
          icon: LucideIcons.table,
          dense: widget.dense,
          onPressed: empty || _busy
              ? null
              : () => _run(
                  () => shareEntriesCsv(
                    entriesToCsv(widget.entries),
                    filename: pillrExportFileName(
                      report: widget.title,
                      scope: _periodScope,
                      on: now,
                      extension: 'csv',
                    ),
                    subject: '$church — ${widget.title}',
                  ),
                ),
        ),
      ],
    );
  }
}
