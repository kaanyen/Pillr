import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/entry_export.dart';
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
    this.dense = true,
  });

  final List<PartnershipEntry> entries;
  final String title;

  /// Describes the current filter, so an exported PDF says what it contains.
  final String? subtitle;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final church = ref.watch(churchNameProvider);
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final empty = widget.entries.isEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SelButton(
          label: 'PDF',
          icon: LucideIcons.fileDown,
          dense: widget.dense,
          onPressed: empty || _busy
              ? null
              : () => _run(() => shareEntriesPdf(
                    title: widget.title,
                    subtitle: widget.subtitle ??
                        '${widget.entries.length} entries',
                    entries: widget.entries,
                    columnHeaders: const [
                      'Partner', 'Amount', 'Status', 'Period', 'Arm', 'Date',
                    ],
                    formatAmount: money,
                    footerBrand: church,
                    exporterLine: profile == null
                        ? null
                        : 'Exported by ${profile.fullName}',
                  )),
        ),
        const SizedBox(width: SelSpace.x2),
        SelButton(
          label: 'CSV',
          icon: LucideIcons.table,
          dense: widget.dense,
          onPressed: empty || _busy
              ? null
              : () => _run(() => shareEntriesCsv(
                    entriesToCsv(widget.entries),
                    subject: '${widget.title} — ${widget.entries.length} entries',
                  )),
        ),
      ],
    );
  }
}
