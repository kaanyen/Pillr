import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../design/seline.dart';
import '../features/entries/monthly_records_index.dart';
import '../features/entries/monthly_records_models.dart';

/// Browse approved giving month by month — cards first, then a friendly drill-down.
class MonthlyRecordsView extends StatefulWidget {
  const MonthlyRecordsView({
    super.key,
    required this.index,
    required this.money,
    this.loadedEntryCount = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.onLoadMore,
  });

  final MonthlyRecordsIndex index;
  final String Function(num) money;
  final int loadedEntryCount;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback? onLoadMore;

  @override
  State<MonthlyRecordsView> createState() => _MonthlyRecordsViewState();
}

class _MonthlyRecordsViewState extends State<MonthlyRecordsView> {
  MonthBucket? _selectedMonth;
  String? _selectedFellowshipKey;
  String? _selectedFellowshipName;

  List<MonthSummary> get _summaries => widget.index.summaries;

  void _openMonth(MonthBucket month) {
    setState(() {
      _selectedMonth = month;
      _selectedFellowshipKey = null;
      _selectedFellowshipName = null;
    });
  }

  void _openFellowship(String key, String name) {
    setState(() {
      _selectedFellowshipKey = key;
      _selectedFellowshipName = name;
    });
  }

  void _backToMonth() {
    setState(() {
      _selectedFellowshipKey = null;
      _selectedFellowshipName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_summaries.isEmpty) {
      return SelCard(
        child: SelEmpty(
          title: 'No monthly giving yet',
          message:
              'Approved entries will appear here grouped by the month they were given.',
          icon: LucideIcons.calendar,
        ),
      );
    }

    if (_selectedMonth == null) {
      return _MonthPicker(
        summaries: _summaries,
        money: widget.money,
        onSelect: _openMonth,
        loadedEntryCount: widget.loadedEntryCount,
        hasMore: widget.hasMore,
        loadingMore: widget.loadingMore,
        onLoadMore: widget.onLoadMore,
      );
    }

    if (_selectedFellowshipKey != null && _selectedFellowshipName != null) {
      return _FellowshipMonthDetail(
        index: widget.index,
        month: _selectedMonth!,
        fellowshipKey: _selectedFellowshipKey!,
        fellowshipName: _selectedFellowshipName!,
        money: widget.money,
        onBack: _backToMonth,
      );
    }

    return _MonthDetail(
      index: widget.index,
      month: _selectedMonth!,
      money: widget.money,
      onBack: () => setState(() => _selectedMonth = null),
      onMonthChanged: (month) => _openMonth(month),
      onFellowshipTap: _openFellowship,
    );
  }
}

class _MonthPicker extends StatelessWidget {
  const _MonthPicker({
    required this.summaries,
    required this.money,
    required this.onSelect,
    this.loadedEntryCount = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.onLoadMore,
  });

  final List<MonthSummary> summaries;
  final String Function(num) money;
  final ValueChanged<MonthBucket> onSelect;
  final int loadedEntryCount;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final now = MonthBucket.fromDate(DateTime.now());
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 900 ? 3 : (width >= 560 ? 2 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick a month to see who gave and how fellowships contributed.',
          style: SelType.bodyMuted,
        ),
        const SizedBox(height: SelSpace.x6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: SelSpace.x4,
            mainAxisSpacing: SelSpace.x4,
            childAspectRatio: crossAxisCount == 1 ? 2.6 : (crossAxisCount == 2 ? 1.35 : 1.15),
          ),
          itemCount: summaries.length,
          itemBuilder: (context, index) {
            final summary = summaries[index];
            final isCurrent = summary.month == now;
            return _MonthCard(
              summary: summary,
              money: money,
              isCurrent: isCurrent,
              onTap: () => onSelect(summary.month),
            );
          },
        ),
        if (loadedEntryCount > 0) ...[
          const SizedBox(height: SelSpace.x6),
          Text(
            hasMore
                ? 'Showing $loadedEntryCount approved entries. Scroll for earlier months.'
                : 'All $loadedEntryCount approved entries loaded.',
            style: SelType.caption,
            textAlign: TextAlign.center,
          ),
        ],
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.only(top: SelSpace.x4),
            child: Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: PillrLoader(size: 20),
              ),
            ),
          )
        else if (hasMore && onLoadMore != null)
          Padding(
            padding: const EdgeInsets.only(top: SelSpace.x4),
            child: Center(
              child: SelButton(
                label: 'Load earlier giving',
                icon: LucideIcons.chevronsDown,
                kind: SelButtonKind.quiet,
                onPressed: onLoadMore,
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthCard extends StatefulWidget {
  const _MonthCard({
    required this.summary,
    required this.money,
    required this.isCurrent,
    required this.onTap,
  });

  final MonthSummary summary;
  final String Function(num) money;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  State<_MonthCard> createState() => _MonthCardState();
}

class _MonthCardState extends State<_MonthCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover ? Sel.card : Sel.canvas,
            borderRadius: BorderRadius.circular(SelRadius.card),
            border: Border.all(
              color: widget.isCurrent ? Sel.ink : Sel.border,
              width: widget.isCurrent ? 1.5 : 1,
            ),
            boxShadow: _hover ? SelShadow.card : const [],
          ),
          padding: const EdgeInsets.all(SelSpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.calendar, size: 16, color: Sel.ink),
                  const SizedBox(width: SelSpace.x2),
                  Expanded(
                    child: Text(
                      summary.month.label,
                      style: SelType.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SelSpace.x2,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Sel.soot,
                        borderRadius: BorderRadius.circular(SelRadius.pill),
                      ),
                      child: Text(
                        'This month',
                        style: SelType.small.copyWith(color: Sel.card),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: SelSpace.x3),
              Text(
                widget.money(summary.approvedTotal),
                style: SelType.title.copyWith(fontFeatures: const [
                  FontFeature.tabularFigures(),
                ]),
              ),
              const SizedBox(height: SelSpace.x1),
              Text(
                '${summary.entryCount} entries · '
                '${summary.partnerCount} partners · '
                '${summary.fellowshipCount} fellowships',
                style: SelType.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  Text('View month', style: SelType.button.copyWith(color: Sel.cyan)),
                  const SizedBox(width: SelSpace.x1),
                  Icon(LucideIcons.arrowRight, size: 14, color: Sel.cyan),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthDetail extends StatefulWidget {
  const _MonthDetail({
    required this.index,
    required this.month,
    required this.money,
    required this.onBack,
    required this.onMonthChanged,
    required this.onFellowshipTap,
  });

  final MonthlyRecordsIndex index;
  final MonthBucket month;
  final String Function(num) money;
  final VoidCallback onBack;
  final ValueChanged<MonthBucket> onMonthChanged;
  final void Function(String key, String name) onFellowshipTap;

  @override
  State<_MonthDetail> createState() => _MonthDetailState();
}

class _MonthDetailState extends State<_MonthDetail> {
  bool _individualsOpen = true;
  bool _fellowshipsOpen = true;

  @override
  Widget build(BuildContext context) {
    final summary = widget.index.summaryFor(widget.month);
    if (summary == null) {
      return SelEmpty(
        title: 'No giving this month',
        message: 'Pick another month from the list.',
      );
    }
    final previous = widget.index.adjacentMonth(widget.month, forward: false);
    final next = widget.index.adjacentMonth(widget.month, forward: true);

    final individuals = widget.index.partnersInMonth(widget.month);
    final fellowships = widget.index.fellowshipsInMonth(widget.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelButton(
          label: 'All months',
          icon: LucideIcons.arrowLeft,
          kind: SelButtonKind.quiet,
          dense: true,
          onPressed: widget.onBack,
        ),
        const SizedBox(height: SelSpace.x4),
        Row(
          children: [
            _MonthNavButton(
              label: previous?.shortLabel ?? '',
              icon: LucideIcons.chevronLeft,
              enabled: previous != null,
              onPressed:
                  previous == null ? null : () => widget.onMonthChanged(previous),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    widget.month.label,
                    style: SelType.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SelSpace.x1),
                  Text(
                    '${widget.money(summary.approvedTotal)} approved · '
                    '${summary.entryCount} entries',
                    style: SelType.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            _MonthNavButton(
              label: next?.shortLabel ?? '',
              icon: LucideIcons.chevronRight,
              enabled: next != null,
              trailing: true,
              onPressed: next == null ? null : () => widget.onMonthChanged(next),
            ),
          ],
        ),
        const SizedBox(height: SelSpace.x8),
        _CollapsibleSection(
          label: 'Individuals',
          trailing: '${individuals.length} partners · '
              '${widget.money(individuals.fold<double>(0, (s, r) => s + r.totalCedis))}',
          expanded: _individualsOpen,
          onToggle: () => setState(() => _individualsOpen = !_individualsOpen),
          child: _IndividualsLedger(rows: individuals, money: widget.money),
        ),
        const SizedBox(height: SelSpace.x6),
        _CollapsibleSection(
          label: 'Fellowships',
          hint: 'Tap a fellowship to see who gave in that group this month.',
          trailing: '${fellowships.length} groups · '
              '${widget.money(fellowships.fold<double>(0, (s, r) => s + r.totalCedis))}',
          expanded: _fellowshipsOpen,
          onToggle: () => setState(() => _fellowshipsOpen = !_fellowshipsOpen),
          child: _FellowshipsLedger(
            rows: fellowships,
            money: widget.money,
            onFellowshipTap: widget.onFellowshipTap,
          ),
        ),
      ],
    );
  }
}

class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    required this.label,
    required this.child,
    required this.expanded,
    required this.onToggle,
    this.hint,
    this.trailing,
  });

  final String label;
  final Widget child;
  final bool expanded;
  final VoidCallback onToggle;
  final String? hint;
  final String? trailing;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SelSpace.x1),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: widget.expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: _hover ? Sel.ink : Sel.ash,
                    ),
                  ),
                  const SizedBox(width: SelSpace.x1),
                  Expanded(child: Text(widget.label, style: SelType.subtitle)),
                  if (widget.trailing != null)
                    Text(widget.trailing!, style: SelType.caption),
                ],
              ),
            ),
          ),
        ),
        if (widget.hint != null && widget.expanded) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: SelSpace.x6,
              bottom: SelSpace.x3,
            ),
            child: Text(widget.hint!, style: SelType.bodyMuted),
          ),
        ],
        if (widget.expanded)
          Padding(
            padding: EdgeInsets.only(
              top: widget.hint == null ? SelSpace.x2 : 0,
              bottom: SelSpace.x2,
            ),
            child: widget.child,
          ),
      ],
    );
  }
}

class _FellowshipMonthDetail extends StatelessWidget {
  const _FellowshipMonthDetail({
    required this.index,
    required this.month,
    required this.fellowshipKey,
    required this.fellowshipName,
    required this.money,
    required this.onBack,
  });

  final MonthlyRecordsIndex index;
  final MonthBucket month;
  final String fellowshipKey;
  final String fellowshipName;
  final String Function(num) money;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final members = index.partnersInMonthForFellowship(
      month,
      fellowshipKey,
    );
    final total = members.fold<double>(0, (sum, row) => sum + row.totalCedis);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelButton(
          label: month.label,
          icon: LucideIcons.arrowLeft,
          kind: SelButtonKind.quiet,
          dense: true,
          onPressed: onBack,
        ),
        const SizedBox(height: SelSpace.x4),
        Text(fellowshipName, style: SelType.title),
        const SizedBox(height: SelSpace.x1),
        Text(
          '${money(total)} approved · ${members.length} partners',
          style: SelType.bodyMuted,
        ),
        const SizedBox(height: SelSpace.x6),
        _IndividualsLedger(rows: members, money: money),
      ],
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.trailing = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: SelButton(
        label: label.isEmpty ? (trailing ? 'Next' : 'Previous') : label,
        icon: icon,
        kind: SelButtonKind.quiet,
        dense: true,
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}

class _IndividualsLedger extends StatelessWidget {
  const _IndividualsLedger({required this.rows, required this.money});

  final List<MonthPartnerGiving> rows;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return SelCard(
        child: SelEmpty(
          title: 'No individual giving',
          message: 'Nobody gave in this month.',
          icon: LucideIcons.user,
        ),
      );
    }

    return SelLedger(
      virtualized: rows.length > 30,
      minWidth: 560,
      columns: const [
        SelColumn('Partner', flex: 3),
        SelColumn.numeric('Entries', width: 90),
        SelColumn.numeric('Approved giving', width: 170),
      ],
      rows: [
        for (final row in rows)
          SelRow(
            onTap: () => context.go('/partners/${row.partnerId}'),
            cells: [
              SelCell.primary(row.partnerName),
              SelCell.numeric('${row.entryCount}'),
              SelCell.numeric(money(row.totalCedis)),
            ],
          ),
      ],
    );
  }
}

class _FellowshipsLedger extends StatelessWidget {
  const _FellowshipsLedger({
    required this.rows,
    required this.money,
    required this.onFellowshipTap,
  });

  final List<MonthFellowshipGiving> rows;
  final String Function(num) money;
  final void Function(String key, String name) onFellowshipTap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return SelCard(
        child: SelEmpty(
          title: 'No fellowship giving',
          message: 'No fellowship recorded giving in this month.',
          icon: LucideIcons.users,
        ),
      );
    }

    return SelLedger(
      virtualized: rows.length > 30,
      minWidth: 560,
      columns: const [
        SelColumn('Fellowship', flex: 3),
        SelColumn.numeric('Partners', width: 100),
        SelColumn.numeric('Approved giving', width: 170),
      ],
      rows: [
        for (final row in rows)
          SelRow(
            onTap: () => onFellowshipTap(row.fellowshipKey, row.fellowshipName),
            cells: [
              SelCell.primary(row.fellowshipName),
              SelCell.numeric('${row.partnerCount}'),
              SelCell.numeric(money(row.totalCedis)),
            ],
          ),
      ],
    );
  }
}
