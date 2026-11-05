import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/panel_flows.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/leaderboard/giving_view.dart';
import '../features/maintenance/providers/duplicate_health_provider.dart';
import '../features/partners/providers/partners_providers.dart';
import 'views/view_common.dart';

/// Partners · All partners — the directory. Ranked is its own destination now
/// (`/ranked`), straight after Partners in the sidebar.
class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  bool _includeInactive = false;
  String _query = '';
  String? _fellowship;

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final partnersAsync = ref.watch(partnersStreamProvider(_includeInactive));
    final active = ref.watch(partnersStreamProvider(false)).valueOrNull ?? const [];
    final everyone = ref.watch(partnersStreamProvider(true)).valueOrNull;
    final closed = everyone == null ? 0 : everyone.length - active.length;
    final view = ref.watch(givingViewProvider);
    final giving = {for (final p in view.partners) p.partnerId: p};
    final dupes = ref.watch(duplicateBadgeCountProvider);

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(partnersStreamProvider(_includeInactive));
        ref.invalidate(rankingEntriesProvider);
        invalidateEntryDerivedData(ref);
      },
      children: [
        SelPageTitle(
          title: 'Partners',
          subtitle: '${active.length} active · $closed closed',
          actions: [
            SelButton.cyan(
              label: 'Add partner',
              icon: LucideIcons.plus,
              onPressed: idx == null
                  ? null
                  : () => showPartnerFormPanel(
                      context,
                      churchId: idx.churchId,
                      uid: idx.uid,
                    ),
            ),
          ],
        ),
        if (dupes > 0) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
            decoration: BoxDecoration(
              color: Sel.skyTint,
              borderRadius: BorderRadius.circular(SelRadius.pill),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$dupes ${dupes == 1 ? 'person may be' : 'people may be'} on the book twice',
                    style: SelType.bodyMedium,
                  ),
                ),
                SelButton(
                  label: 'Review in Tools',
                  dense: true,
                  onPressed: () => context.go('/tools'),
                ),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        partnersAsync.when(
          loading: () => const SelCard(child: SelSkeletonRows()),
          error: (e, _) => SelError(message: '$e'),
          data: (partners) {
            final counts = <String, (String, int)>{};
            for (final p in partners) {
              final k = p.fellowship.trim().toLowerCase();
              final c = counts[k];
              counts[k] = (p.fellowship.trim().isEmpty ? 'No fellowship' : p.fellowship, (c?.$2 ?? 0) + 1);
            }
            final groups = counts.entries.toList()
              ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
            final rows = partners.where((p) {
              if (_fellowship != null &&
                  p.fellowship.trim().toLowerCase() != _fellowship) {
                return false;
              }
              if (_query.isEmpty) return true;
              return p.fullName.toLowerCase().contains(_query) ||
                  p.memberId.toLowerCase().contains(_query) ||
                  p.formerMemberIds.any((id) => id.toLowerCase().contains(_query)) ||
                  p.allPhones.any((ph) => ph.contains(_query));
            }).toList()
              ..sort((a, b) => a.fullName.compareTo(b.fullName));

            return SelCard(
              padding: EdgeInsets.zero,
              clip: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FellowTab(
                            label: 'All',
                            count: partners.length,
                            on: _fellowship == null,
                            onTap: () => setState(() => _fellowship = null),
                          ),
                          for (final g in groups)
                            _FellowTab(
                              label: g.value.$1,
                              count: g.value.$2,
                              on: _fellowship == g.key,
                              onTap: () => setState(() => _fellowship = g.key),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelField(
                            hint: 'Name, member ID, old ID or phone',
                            prefixIcon: LucideIcons.search,
                            onChanged: (v) =>
                                setState(() => _query = v.trim().toLowerCase()),
                          ),
                        ),
                        const SizedBox(width: SelSpace.x3),
                        SelButton(
                          label: _includeInactive
                              ? 'Hide closed partners'
                              : '+ Closed partners',
                          dense: true,
                          onPressed: () => setState(
                            () => _includeInactive = !_includeInactive,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SelLedger.builder(
                    bare: true,
                    minWidth: 900,
                    maxVirtualHeight: 760,
                    rowExtent: kSelLedgerStackedRowExtent,
                    columns: const [
                      SelColumn('Partner', flex: 4),
                      SelColumn('Member ID', fit: SelColFit.fixed, width: 130),
                      SelColumn('Fellowship', flex: 2),
                      SelColumn.numeric('Giving this year', width: 160),
                      SelColumn.numeric('Entries', width: 90),
                      SelColumn.numeric('Last giving', width: 120),
                    ],
                    emptyState: SelEmpty(
                      title: _query.isEmpty ? 'No partners yet' : 'No matches',
                      message: _query.isEmpty
                          ? 'Add partners to start recording their giving.'
                          : 'Nothing matches “$_query”.',
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final p = rows[i];
                      final g = giving[p.id];
                      final phone = p.allPhones.isEmpty ? '' : p.allPhones.first;
                      final digits = phone.replaceAll(RegExp(r'\D'), '');
                      final note = [
                        if (p.mergedAliases.isNotEmpty)
                          'Merged from ${p.mergedAliases.length + 1}'
                        else if (digits.length >= 4)
                          'Phone ending ${digits.substring(digits.length - 4)}'
                        else
                          'No phone',
                        if (!p.isActive) 'closed',
                      ].join(' · ');
                      return SelRow(
                        onTap: () => context.go('/partners/${p.id}'),
                        cells: [
                          Row(
                            children: [
                              _Initials(name: p.fullName),
                              const SizedBox(width: SelSpace.x3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      p.fullName,
                                      style: SelType.body.copyWith(
                                        color: Sel.text,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(note, style: SelType.small, maxLines: 1),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Text(
                            p.memberId,
                            style: SelType.small.copyWith(fontFamily: 'monospace'),
                          ),
                          SelCell.secondary(p.fellowship),
                          SelCell.numeric(
                            money(g?.total ?? 0),
                            strong: (g?.total ?? 0) > 0,
                          ),
                          SelCell.numeric('${g?.entries ?? 0}', strong: false),
                          SelCell.numeric(gaveOn(g?.lastGave), strong: false),
                        ],
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                    child: Text(
                      '${rows.length} of ${partners.length} ${_includeInactive ? 'partners' : 'active'}',
                      style: SelType.small,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FellowTab extends StatelessWidget {
  const _FellowTab({
    required this.label,
    required this.count,
    required this.on,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Sel.card : Sel.text;
    return Padding(
      padding: const EdgeInsets.only(right: SelSpace.x1),
      child: Material(
        color: on ? Sel.ink : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: SelType.body.copyWith(color: fg)),
                const SizedBox(width: SelSpace.x2),
                Text(
                  '$count',
                  style: SelType.body.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Sel.skyTint, shape: BoxShape.circle),
      child: Text(
        words.take(2).map((w) => w[0].toUpperCase()).join(),
        style: SelType.tag.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}
