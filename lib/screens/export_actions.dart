import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
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
        selNotice(context, 'Export failed: $e', kind: SelNoticeKind.error);
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

  String _filterScopeLabel() {
    final subtitle = widget.subtitle?.trim();
    if (subtitle != null && subtitle.isNotEmpty) return subtitle;
    return 'Giving';
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
                    subtitle: widget.subtitle ?? _filterScopeLabel(),
                    entries: widget.entries,
                    columnHeaders: const [],
                    logoUrl: logoUrl,
                    generatedAtLine: l10n.pdfGeneratedAt(when),
                    exporterLine: profile == null
                        ? null
                        : l10n.pdfExporter(profile.fullName),
                    organizationName: church,
                    ministryYear: _periodScope,
                    exporterName: profile?.fullName,
                    currencySymbol: currency,
                    generatedAt: now,
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
