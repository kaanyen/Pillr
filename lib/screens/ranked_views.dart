import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../design/seline.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/record_filters.dart';
import '../features/leaderboard/leaderboard_models.dart';
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

class PartnerRankedLedger extends StatelessWidget {
  const PartnerRankedLedger({
    super.key,required this.rows, required this.money});

  final List<LeaderboardRow> rows;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
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
