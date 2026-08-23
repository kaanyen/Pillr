import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../l10n/app_localizations.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/partners/domain/partner.dart';
import '../features/partners/providers/partners_providers.dart';

/// Global search across partners and entries. Pastor only.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _q = TextEditingController();
  List<Partner> _partners = [];
  List<PartnershipEntry> _entries = [];
  bool _busy = false;
  bool _ran = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Timer? _debounce;
  int _seq = 0;

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _run);
  }

  /// Runs the current query.
  ///
  /// Every run carries a sequence number and a slow answer to an old query is
  /// dropped: typing "Kwe" then "Kweku" must not end with the results for
  /// "Kwe" landing last.
  Future<void> _run() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    final query = _q.text.trim();
    final seq = ++_seq;

    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _error = null;
        _partners = [];
        _entries = [];
        _busy = false;
        _ran = query.isNotEmpty;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Staff see the entries they recorded; a pastor sees the church's.
      final partnersFuture = ref
          .read(partnersRepositoryProvider)
          .searchPartners(idx.churchId, query);
      final pageFuture = ref
          .read(entriesRepositoryProvider)
          .fetchEntriesPage(
            idx.churchId,
            allChurchEntries: idx.isPastor,
            createdByUid: idx.isPastor ? null : idx.uid,
            pageSize: 80,
          );
      final partners = await partnersFuture;
      final page = await pageFuture;
      if (!mounted || seq != _seq) return;

      final lower = query.toLowerCase();
      final entries = page.items.where((e) {
        final name =
            e.partnerSnapshot['fullName']?.toString().toLowerCase() ?? '';
        final memberId =
            e.partnerSnapshot['memberId']?.toString().toLowerCase() ?? '';
        return name.contains(lower) ||
            memberId.contains(lower) ||
            e.status.toLowerCase().contains(lower);
      }).toList();

      setState(() {
        _partners = partners;
        _entries = entries;
        _busy = false;
        _ran = true;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = ref.watch(churchMoneyFormatProvider);

    return SelPageBody(
      maxWidth: 900,
      children: [
        SelPageTitle(title: l10n.titleSearch, subtitle: l10n.searchSubtitle),
        // No Search button: a button is a second thing to do after typing,
        // and results that arrive as you type tell you whether to keep going.
        Row(
          children: [
            Expanded(
              child: SelField(
                controller: _q,
                hint: l10n.searchFieldHint,
                prefixIcon: LucideIcons.search,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: (_) => _run(),
              ),
            ),
            // A quiet sign that the answer is still coming, where a button
            // used to sit.
            SizedBox(
              width: SelSpace.x8,
              child: Center(
                child: _busy
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Sel.ash,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: SelSpace.x3),
          Text(_error!, style: SelType.bodySm.copyWith(color: Sel.ink)),
        ],
        const SizedBox(height: SelSpace.x8),

        if (!_ran)
          SelCard(
            child: SelEmpty(
              title: l10n.searchIdleTitle,
              message:
                  'Type a name, a member ID or a status. '
                  'Results appear as you go.',
              icon: LucideIcons.search,
            ),
          )
        else ...[
          SelSectionLabel(
            label: 'Partners',
            trailing: Text('${_partners.length}', style: SelType.bodyMuted),
          ),
          SelLedger(
            minWidth: 520,
            columns: const [
              SelColumn('Member ID', fit: SelColFit.fixed, width: 120),
              SelColumn('Name', flex: 2),
              SelColumn.numeric('Total given', width: 140),
            ],
            emptyState: SelEmpty(
              title: l10n.searchNoPartners,
              message: 'Try a different spelling or a member ID.',
            ),
            rows: [
              for (final p in _partners)
                SelRow(
                  onTap: () => context.go('/partners/${p.id}'),
                  cells: [
                    SelCell.secondary(p.memberId),
                    SelCell.primary(p.fullName),
                    SelCell.numeric(money(p.totalApprovedAmount)),
                  ],
                ),
            ],
          ),
          const SelSectionGap(factor: 0.5),
          SelSectionLabel(
            label: 'Entries',
            trailing: Text('${_entries.length}', style: SelType.bodyMuted),
          ),
          SelLedger(
            minWidth: 620,
            columns: const [
              SelColumn('Partner', flex: 2),
              SelColumn.numeric('Amount', width: 130),
              SelColumn('Status', fit: SelColFit.fixed, width: 120),
              SelColumn('Date', fit: SelColFit.fixed, width: 110),
            ],
            emptyState: SelEmpty(
              title: l10n.searchNoEntries,
              message: 'Search covers the most recent 80 entries.',
            ),
            rows: [
              for (final e in _entries)
                SelRow(
                  onTap: () => context.go('/entries/${e.id}'),
                  cells: [
                    SelCell.primary(
                      e.partnerSnapshot['fullName']?.toString() ?? '—',
                    ),
                    SelCell.numeric(
                      money(e.amountCedis),
                      tone: switch (e.status) {
                        'approved' => SelTone.positive,
                        'declined' => SelTone.negative,
                        _ => SelTone.neutral,
                      },
                    ),
                    SelStatusMark.fromString(
                      status: e.status,
                      label: e.status[0].toUpperCase() + e.status.substring(1),
                    ),
                    SelCell.secondary(
                      formatFirestoreDate(e.createdAt, pattern: 'd MMM'),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
