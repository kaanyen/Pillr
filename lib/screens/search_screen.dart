import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
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
    _q.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isPastor) return;
    final query = _q.text.trim();
    if (query.length < 2) {
      setState(() {
        _error = 'Enter at least 2 characters.';
        _partners = [];
        _entries = [];
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final partners = await ref
          .read(partnersRepositoryProvider)
          .searchPartners(idx.churchId, query);
      final page = await ref.read(entriesRepositoryProvider).fetchEntriesPage(
            idx.churchId,
            allChurchEntries: true,
            pageSize: 80,
          );
      final lower = query.toLowerCase();
      final entries = page.items.where((e) {
        final name = e.partnerSnapshot['fullName']?.toString().toLowerCase() ?? '';
        return name.contains(lower) || e.status.toLowerCase().contains(lower);
      }).toList();
      if (!mounted) return;
      setState(() {
        _partners = partners;
        _entries = entries;
        _busy = false;
        _ran = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);

    return SelPageBody(
      maxWidth: 900,
      children: [
        const SelPageTitle(
          title: 'Search',
          subtitle: 'Find a partner or an entry across your church.',
        ),
        Row(
          children: [
            Expanded(
              child: SelField(
                controller: _q,
                hint: 'Name, member ID or status',
                prefixIcon: LucideIcons.search,
                autofocus: true,
                onSubmitted: (_) => _run(),
              ),
            ),
            const SizedBox(width: SelSpace.x3),
            SelButton.cyan(label: 'Search', loading: _busy, onPressed: _run),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: SelSpace.x3),
          Text(_error!, style: SelType.bodySm.copyWith(color: Sel.ink)),
        ],
        const SizedBox(height: SelSpace.x8),

        if (!_ran)
          const SelCard(
            child: SelEmpty(
              title: 'Search your church',
              message: 'Results appear here once you search.',
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
            emptyState: const SelEmpty(
              title: 'No partners matched',
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
            emptyState: const SelEmpty(
              title: 'No entries matched',
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
