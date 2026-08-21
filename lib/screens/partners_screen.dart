import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/leaderboard/leaderboard_models.dart';
import '../features/partners/presentation/partner_form_dialog.dart';
import '../features/partners/providers/partners_providers.dart';
import 'export_actions.dart';
import '../features/periods/providers/periods_providers.dart';

enum _View { directory, ranked }

/// Partners — the directory, with Leaderboard folded in as a second view.
///
/// Leaderboard was never a separate concern: it is the same partner records
/// ordered by approved giving. Making it a view toggle rather than a nav item
/// removes a destination and puts the ranking one click from the profile it
/// describes.
class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key, this.initialView});

  /// Lets `/leaderboard` land here on the ranked view.
  final String? initialView;

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  late _View _view =
      widget.initialView == 'ranked' ? _View.ranked : _View.directory;
  bool _includeInactive = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final partnersAsync = ref.watch(partnersStreamProvider(_includeInactive));
    final isPastor = idx?.isPastor ?? false;

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(partnersStreamProvider(_includeInactive));
        ref.invalidate(entriesListProvider);
      },
      children: [
        SelPageTitle(
          title: 'Partners',
          subtitle: _view == _View.directory
              ? 'Everyone with a giving record in your church.'
              : 'Ranked by approved giving in the active period.',
          actions: [
            if (_view == _View.ranked)
              EntryExportButtons(
                entries: ref.watch(entriesListProvider).valueOrNull ?? [],
                title: 'Partner ranking',
                subtitle: 'Ranked by approved giving',
              ),
            if (_view == _View.ranked) const SizedBox(width: SelSpace.x2),
            SelButton.cyan(
              label: 'Add partner',
              icon: LucideIcons.plus,
              onPressed: idx == null
                  ? null
                  : () => showDialog(
                        context: context,
                        builder: (_) => PartnerFormDialog(
                          churchId: idx.churchId,
                          uid: idx.uid,
                        ),
                      ),
            ),
          ],
        ),

        Row(
          children: [
            SelPillGroup<_View>(
              selected: _view,
              onChanged: (v) => setState(() => _view = v),
              options: const [
                (_View.directory, 'Directory'),
                (_View.ranked, 'Ranked'),
              ],
            ),
            const Spacer(),
            if (_view == _View.directory) ...[
              SizedBox(
                width: 240,
                child: SelField(
                  hint: 'Search name or member ID',
                  prefixIcon: LucideIcons.search,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: SelSpace.x3),
              SelButton(
                label: _includeInactive ? 'Hide inactive' : 'Show inactive',
                kind: SelButtonKind.quiet,
                dense: true,
                onPressed: () =>
                    setState(() => _includeInactive = !_includeInactive),
              ),
            ],
          ],
        ),

        const SizedBox(height: SelSpace.x6),

        if (_view == _View.directory)
          partnersAsync.when(
            loading: () => const SelCard(child: SelSkeletonRows()),
            error: (e, _) => SelError(message: '$e'),
            data: (partners) {
              final rows = partners.where((p) {
                if (_query.isEmpty) return true;
                return p.fullName.toLowerCase().contains(_query) ||
                    p.memberId.toLowerCase().contains(_query) ||
                    p.fellowship.toLowerCase().contains(_query);
              }).toList();

              return SelLedger(
                minWidth: 720,
                columns: const [
                  SelColumn('Member ID', fit: SelColFit.fixed, width: 120),
                  SelColumn('Name', flex: 3),
                  SelColumn('Fellowship', flex: 2),
                  SelColumn.numeric('Total given', width: 140),
                  SelColumn('Status', fit: SelColFit.fixed, width: 110),
                ],
                emptyState: SelEmpty(
                  title: _query.isEmpty ? 'No partners yet' : 'No matches',
                  message: _query.isEmpty
                      ? 'Add partners to start recording their giving.'
                      : 'Nothing matches “$_query”.',
                ),
                rows: [
                  for (final p in rows)
                    SelRow(
                      onTap: () => context.go('/partners/${p.id}'),
                      cells: [
                        SelCell.secondary(p.memberId),
                        SelCell.primary(p.fullName),
                        SelCell.secondary(p.fellowship),
                        SelCell.numeric(money(p.totalApprovedAmount)),
                        SelStatusMark(
                          status: p.isActive
                              ? SelStatus.active
                              : SelStatus.inactive,
                          label: p.isActive ? 'Active' : 'Inactive',
                        ),
                      ],
                    ),
                ],
              );
            },
          )
        else
          _RankedView(money: money, isPastor: isPastor),
      ],
    );
  }
}

/// Ranked view. Rank is a plain figure — no medals, no colour. Position is
/// already the information; decorating it would spend chromatic budget the
/// system reserves for actions.
class _RankedView extends ConsumerWidget {
  const _RankedView({required this.money, required this.isPastor});

  final String Function(num) money;
  final bool isPastor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(entriesListProvider).valueOrNull ?? [];
    final period = ref.watch(activePeriodProvider);
    final rows = LeaderboardRow.fromEntries(entries, periodId: period?.id);

    if (rows.isEmpty) {
      return const SelCard(
        child: SelEmpty(
          title: 'Nothing ranked yet',
          message: 'Rankings appear once entries are approved in this period.',
          icon: LucideIcons.trophy,
        ),
      );
    }

    return SelLedger(
      minWidth: 520,
      columns: const [
        SelColumn('Rank', fit: SelColFit.fixed, width: 70),
        SelColumn('Partner', flex: 3),
        SelColumn.numeric('Approved giving', width: 170),
      ],
      rows: [
        for (final r in rows)
          SelRow(
            onTap: () => context.go('/partners/${r.partnerId}'),
            cells: [
              Text(
                '${r.rank}',
                style: SelType.body.copyWith(
                  color: r.rank <= 3 ? Sel.ink : Sel.ash,
                  fontWeight: r.rank <= 3 ? FontWeight.w500 : FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SelCell.primary(r.partnerName),
              SelCell.numeric(money(r.totalCedis)),
            ],
          ),
      ],
    );
  }
}
