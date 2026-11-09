import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../design/seline.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/record_filters.dart';
import '../features/leaderboard/leaderboard_models.dart';
import '../features/partners/providers/partners_providers.dart';
import 'record_filter_bar.dart';

class RankGroupSection {
  const RankGroupSection({
    required this.title,
    required this.rows,
    required this.emptyTitle,
    required this.emptyMessage,
    this.icon,
    this.trailing,
    this.showWhenEmpty = false,
  });

  final String title;
  final IconData? icon;
  final List<LeaderboardRow> rows;
  final String emptyTitle;
  final String emptyMessage;
  final String? trailing;
  final bool showWhenEmpty;
}

class RankedGroupedBody extends StatelessWidget {
  const RankedGroupedBody({
    super.key,
    required this.money,
    required this.all,
    required this.arms,
    required this.filters,
    required this.sections,
    required this.requireAnyRows,
    this.intro,
  });

  final String Function(num) money;
  final List<PartnershipEntry> all;
  final List<PartnershipArm> arms;
  final RecordFilters filters;
  final List<RankGroupSection> sections;
  final bool requireAnyRows;
  final Widget? intro;

  @override
  Widget build(BuildContext context) {
    if (!requireAnyRows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RecordFilterBar(entries: all, arms: arms),
          const SizedBox(height: SelSpace.x4),
          SelCard(
            child: SelEmpty(
              title: filters.isEmpty ? 'Nothing ranked yet' : 'Nothing matches',
              message: filters.isEmpty
                  ? 'Rankings appear once entries are approved in this period.'
                  : 'No approved giving matches these filters.',
              icon: LucideIcons.trophy,
            ),
          ),
        ],
      );
    }

    final visible = sections
        .where((section) => section.showWhenEmpty || section.rows.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecordFilterBar(entries: all, arms: arms),
        if (intro != null) ...[
          const SizedBox(height: SelSpace.x4),
          intro!,
        ],
        const SizedBox(height: SelSpace.x6),
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SelSectionGap(factor: 0.5),
          RankGroupSectionView(section: visible[i], money: money),
        ],
      ],
    );
  }
}

class RankGroupSectionView extends StatelessWidget {
  const RankGroupSectionView({
    super.key,required this.section, required this.money});

  final RankGroupSection section;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: SelSpace.x3),
          child: Row(
            children: [
              if (section.icon != null) ...[
                Icon(section.icon, size: 16, color: Sel.ink),
                const SizedBox(width: SelSpace.x2),
              ],
              Expanded(
                child: Text(section.title, style: SelType.subtitle),
              ),
              if (section.trailing != null)
                Text(section.trailing!, style: SelType.caption),
            ],
          ),
        ),
        if (section.rows.isEmpty)
          SelCard(
            child: SelEmpty(
              title: section.emptyTitle,
              message: section.emptyMessage,
              icon: LucideIcons.trophy,
            ),
          )
        else
          PartnerRankedLedger(rows: section.rows, money: money),
      ],
    );
  }
}

/// The ranking table, as on the canvas: a rank badge (navy for the first
/// three), the partner's initials and name, their fellowship, how many
/// approved entries they have in the scope, and what they gave.
class PartnerRankedLedger extends ConsumerWidget {
  const PartnerRankedLedger({
    super.key,
    required this.rows,
    required this.money,
    this.entries,
  });

  final List<LeaderboardRow> rows;
  final String Function(num) money;

  /// The entries the ranking was made from. When given, the table counts each
  /// partner's approved entries in them.
  final List<PartnershipEntry>? entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fellowshipOf = ref.watch(partnerFellowshipByIdProvider);
    final counts = <String, int>{};
    for (final e in entries ?? const <PartnershipEntry>[]) {
      if (e.status == 'approved') {
        counts[e.partnerId] = (counts[e.partnerId] ?? 0) + 1;
      }
    }
    final showCount = entries != null;
    // Builder rather than a finished list: this renders the whole partner
    // ranking, and short per-arm sections still lay out at their natural
    // height because the virtual height clamps to the row count.
    return SelLedger.builder(
      minWidth: 620,
      maxVirtualHeight: 640,
      columns: [
        const SelColumn('Rank', fit: SelColFit.fixed, width: 64),
        const SelColumn('Partner', flex: 3),
        const SelColumn('Fellowship', flex: 2),
        if (showCount) const SelColumn.numeric('Entries', width: 90),
        const SelColumn.numeric('Given this period', width: 170),
      ],
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        final top = r.rank <= 3;
        return SelRow(
          onTap: () => context.go('/partners/${r.partnerId}'),
          cells: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: top ? Sel.ink : Sel.track,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${r.rank}',
                  style: SelType.small.copyWith(
                    color: top ? Sel.card : Sel.ink,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                SelFace(r.partnerName),
                const SizedBox(width: SelSpace.x3),
                Expanded(
                  child: Text(
                    r.partnerName,
                    overflow: TextOverflow.ellipsis,
                    style: SelType.body.copyWith(
                      color: Sel.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            SelCell.secondary(fellowshipOf[r.partnerId] ?? ''),
            if (showCount) SelCell.numeric('${counts[r.partnerId] ?? 0}'),
            Text(
              money(r.totalCedis),
              textAlign: TextAlign.right,
              style: SelType.body.copyWith(
                color: Sel.ink,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}
