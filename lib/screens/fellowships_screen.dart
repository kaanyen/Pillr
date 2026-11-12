import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/entries/providers/record_filters.dart';
import '../features/leaderboard/leaderboard_models.dart';
import '../features/leaderboard/leaderboard_providers.dart';
import '../features/partners/domain/partner.dart';
import '../features/leaderboard/giving_view.dart';
import '../features/partners/providers/partners_providers.dart';
import 'views/view_common.dart';
import '../features/periods/providers/periods_providers.dart';
import 'fellowship_manage_view.dart';
import '../features/fellowships/fellowship_match.dart';
import '../features/fellowships/move_people.dart';
import 'fellowship_rhythm_view.dart';
import 'ranked_views.dart';
import 'record_filter_bar.dart';
import '../core/errors/plain_error.dart';

enum _View { directory, rhythm, ranked, manage }

/// Fellowships — directory of groups, with giving rankings alongside.
///
/// Partners answers "who gives the most in the church?" Fellowships answers
/// "how do Bethel, Zion and Grace compare?" Tap a fellowship to see who
/// leads within that group.
class FellowshipsScreen extends ConsumerStatefulWidget {
  const FellowshipsScreen({
    super.key,
    this.initialView,
    this.initialFellowship,
  });

  final String? initialView;
  final String? initialFellowship;

  @override
  ConsumerState<FellowshipsScreen> createState() => _FellowshipsScreenState();
}

class _FellowshipsScreenState extends ConsumerState<FellowshipsScreen> {
  /// "4 fellowships · 45 partners · 2026 partnership year".
  String _summary(WidgetRef ref) {
    final view = ref.watch(givingViewProvider);
    final partners = view.fellowships.fold<int>(0, (s, f) => s + f.partners);
    final period = ref.watch(activePeriodProvider)?.name;
    return [
      '${view.fellowships.length} fellowships',
      '$partners partners',
      ?period,
    ].join(' · ');
  }

  late _View _view = switch (widget.initialView) {
    'ranked' => _View.ranked,
    'manage' => _View.manage,
    'rhythm' => _View.rhythm,
    _ => _View.directory,
  };
  String _query = '';

  @override
  void initState() {
    super.initState();
    final fellowship = widget.initialFellowship?.trim().toLowerCase();
    if (fellowship != null && fellowship.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(recordFiltersProvider.notifier)
            .set(RecordFilters.empty.withFellowship(fellowship));
      });
    }
  }

  /// A fellowship opens its own page: Overview, People, Arms, Month by month.
  void _openFellowshipMembers(String fellowshipKey) {
    context.go('/fellowships/${Uri.encodeComponent(fellowshipKey)}');
  }

  void _backToAllFellowships() {
    ref.read(recordFiltersProvider.notifier).set(RecordFilters.empty);
    context.go('/fellowships?view=ranked');
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildPage(context);
    } catch (e) {
      return SelPageBody(
        children: [
          const SelPageTitle(
            title: 'Fellowships',
            subtitle: 'The list could not be built.',
          ),
          SelError(message: plainError(e)),
        ],
      );
    }
  }

  Widget _buildPage(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final canManage = idx?.canManageFellowships ?? false;
    final adminOnly = idx?.isAdmin ?? false;
    // Pastors draw the rhythm from the giving they read; staff get counts
    // from the server, with no names or amounts. Admins see no giving.
    final canRhythm = (idx?.isPastor ?? false) || (idx?.isStaff ?? false);
    final countsOnly = !(idx?.isPastor ?? false);
    final view = adminOnly
        ? _View.manage
        : (_view == _View.rhythm && !canRhythm) ||
              (_view == _View.ranked && !(idx?.isPastor ?? false))
        ? _View.directory
        : _view;
    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(partnersStreamProvider(false));
        ref.invalidate(rankingEntriesProvider);
        invalidateEntryDerivedData(ref);
      },
      children: [
        SelPageTitle(
          title: 'Fellowships',
          subtitle: view == _View.manage
              ? 'Create a group, move a partner, rename, merge, or dissolve one into another.'
              : view == _View.rhythm && countsOnly
              ? 'How many partners in each fellowship gave each month. Counts only, no names or amounts.'
              : view == _View.rhythm
              ? 'How many partners in each fellowship gave each month.'
              : _summary(ref),
          actions: [
            if (canManage && view != _View.manage)
              SelButton.cyan(
                label: 'New fellowship',
                icon: LucideIcons.plus,
                onPressed: () => createFellowship(context, ref),
              ),
            if (view == _View.manage && !adminOnly)
              SelButton(
                label: 'Back to the list',
                icon: LucideIcons.arrowLeft,
                onPressed: () => setState(() => _view = _View.directory),
              ),
          ],
        ),
        // What the fellowships look like at a glance, before anything else.
        if (view == _View.directory || view == _View.rhythm) ...[
          const _FellowshipSummary(),
          const SizedBox(height: SelSpace.x6),
        ],
        if (canRhythm && (view == _View.directory || view == _View.rhythm)) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SelTrackTabs<_View>(
              selected: view,
              onSelect: (v) => setState(() => _view = v),
              tabs: const [(_View.directory, 'Totals'), (_View.rhythm, 'Giving rhythm')],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        if (view == _View.directory) ...[
          SizedBox(
            width: 320,
            child: SelField(
              hint: 'Find a fellowship',
              prefixIcon: LucideIcons.search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
        ],
        const SizedBox(height: SelSpace.x4),
        if (view == _View.rhythm)
          FellowshipRhythmView(countsOnly: countsOnly)
        else if (view == _View.directory)
          _FellowshipDirectory(
            query: _query,
            onOpenFellowship: _openFellowshipMembers,
            canManage: canManage,
          )
        else if (view == _View.manage)
          const FellowshipManageView()
        else
          _FellowshipRankedView(
            onOpenFellowship: _openFellowshipMembers,
            onBackToAll: _backToAllFellowships,
          ),
      ],
    );
  }
}

/// Isolated from [FellowshipsScreen.build] so a directory compute error cannot
/// blank the title and view switch. Production was throwing in the parent
/// `build` and leaving an empty canvas.
class _FellowshipDirectory extends ConsumerWidget {
  const _FellowshipDirectory({
    required this.query,
    required this.onOpenFellowship,
    this.canManage = false,
  });

  final String query;

  /// Shows the ⋯ on each row: Move people, Rename, Merge into, Close.
  final bool canManage;
  final ValueChanged<String> onOpenFellowship;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(visiblePartnersProvider(false));
    return partnersAsync.when(
      loading: () => const SelCard(child: SelSkeletonRows()),
      error: (e, _) => SelError(message: plainError(e)),
      data: (partners) => _directoryTable(context, ref, partners),
    );
  }

  Widget _directoryTable(BuildContext context, WidgetRef ref, List<Partner> partners) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final ranks = ref.watch(canSeeRanksProvider);
    // A fellowship nobody is in yet still gets a row, so it can be
    // renamed, filled or closed from here.
    final empty = [
      for (final n in ref.watch(knownFellowshipsProvider))
        if (!view.fellowships.any((f) => fellowshipNamesMatch(f.name, n)))
          FellowshipGiving(key: n.trim().toLowerCase(), name: n),
    ];
    final rows = [
      for (final f in [...view.fellowships, ...empty])
        if (query.isEmpty || f.name.toLowerCase().contains(query)) f,
    ];
    // Staff see no places: what they recorded, not how fellowships compare.
    if (!ranks) rows.sort((a, b) => a.name.compareTo(b.name));
    Widget amountWithPlace(double v, int place) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          money(v),
          style: SelType.body.copyWith(
            color: Sel.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 28,
          child: Text(place > 0 && ranks ? ordinal(place) : '', style: SelType.small),
        ),
      ],
    );

    return SelLedger(
      minWidth: 200.0 + view.arms.length * 170 + 150 + (canManage ? 48 : 0),
      columns: [
        const SelColumn('Fellowship', flex: 2),
        const SelColumn.numeric('Partners', width: 90),
        for (final a in view.arms) SelColumn.numeric(a.name, width: 170),
        const SelColumn.numeric('Total', width: 150),
      ],
      emptyState: SelEmpty(
        title: query.isEmpty ? 'No fellowships yet' : 'No matches',
        message: query.isEmpty
            ? 'Fellowships appear once partners are assigned to a group.'
            : 'Nothing matches “$query”.',
        icon: LucideIcons.users,
      ),
      rows: [
        for (final f in rows)
          SelRow(
            onTap: () => onOpenFellowship(f.key),
            cells: [
              // The ⋯ sits beside the name so it is on screen on a phone,
              // where the table scrolls sideways.
              canManage
                  ? Row(
                      children: [
                        Flexible(child: SelCell.primary(f.name)),
                        const SizedBox(width: SelSpace.x1),
                        _FellowshipMenu(name: f.name, partners: f.partners),
                      ],
                    )
                  : SelCell.primary(f.name),
              SelCell.numeric('${f.partners}', strong: false),
              for (final a in view.arms)
                Align(
                  alignment: Alignment.centerRight,
                  child: amountWithPlace(
                    f.byArm[a.id] ?? 0,
                    (f.byArm[a.id] ?? 0) > 0
                        ? view.placeOf(f.key, armId: a.id)
                        : 0,
                  ),
                ),
              SelCell.numeric(money(f.total)),
            ],
          ),
        if (rows.isNotEmpty && query.isEmpty)
          SelRow(
            cells: [
              Text('All', style: SelType.bodyMedium.copyWith(fontWeight: FontWeight.w800)),
              SelCell.numeric('${view.fellowships.fold<int>(0, (s, f) => s + f.partners)}'),
              for (final a in view.arms)
                Padding(
                  padding: const EdgeInsets.only(right: 34),
                  child: SelCell.numeric(money(view.armTotal(a.id))),
                ),
              SelCell.numeric(money(view.total)),
            ],
          ),
      ],
    );
  }
}

class _FellowshipRankedView extends ConsumerWidget {
  const _FellowshipRankedView({
    required this.onOpenFellowship,
    required this.onBackToAll,
  });

  final ValueChanged<String> onOpenFellowship;
  final VoidCallback onBackToAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    late final String Function(num) money;
    try {
      money = ref.watch(churchMoneyFormatProvider);
    } catch (_) {
      money = (n) => n.toStringAsFixed(2);
    }
    final all = ref.watch(rankingEntriesProvider).valueOrNull ?? const [];
    final arms =
        ref.watch(armsStreamProvider).valueOrNull ?? const <PartnershipArm>[];
    final filters = ref.watch(recordFiltersProvider);
    final fellowshipFilter = filters.fellowship?.toLowerCase();

    if (fellowshipFilter != null && fellowshipFilter.isNotEmpty) {
      return _FellowshipMembersDetail(
        money: money,
        all: all,
        arms: arms,
        filters: filters,
        fellowshipKey: fellowshipFilter,
        onBack: onBackToAll,
      );
    }

    late final List<FellowshipRankRow> rows;
    try {
      rows = ref.watch(fellowshipRankingProvider);
    } catch (e) {
      return SelError(message: plainError(e));
    }

    if (rows.isEmpty) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecordFilterBar(entries: all, arms: arms),
        const SizedBox(height: SelSpace.x4),
        SelLedger(
          minWidth: 560,
          columns: const [
            SelColumn('Rank', fit: SelColFit.fixed, width: 70),
            SelColumn('Fellowship', flex: 3),
            SelColumn.numeric('Partners', width: 110),
            SelColumn.numeric('Approved giving', width: 170),
          ],
          rows: [
            for (final row in rows)
              SelRow(
                onTap: () => onOpenFellowship(row.fellowshipKey),
                cells: [
                  Text(
                    '${row.rank}',
                    style: SelType.body.copyWith(
                      color: row.rank <= 3 ? Sel.ink : Sel.ash,
                      fontWeight:
                          row.rank <= 3 ? FontWeight.w500 : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SelCell.primary(row.fellowshipName),
                  SelCell.numeric('${row.partnerCount}'),
                  SelCell.numeric(money(row.totalCedis)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _FellowshipMembersDetail extends ConsumerWidget {
  const _FellowshipMembersDetail({
    required this.money,
    required this.all,
    required this.arms,
    required this.filters,
    required this.fellowshipKey,
    required this.onBack,
  });

  final String Function(num) money;
  final List<PartnershipEntry> all;
  final List<PartnershipArm> arms;
  final RecordFilters filters;
  final String fellowshipKey;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(fellowshipSectionsProvider);
    final section = sections
        .where((s) => s.fellowshipKey == fellowshipKey)
        .firstOrNull;

    return RankedGroupedBody(
      money: money,
      all: all,
      arms: arms,
      filters: filters,
      intro: SelButton(
        label: 'All fellowships',
        icon: LucideIcons.arrowLeft,
        kind: SelButtonKind.quiet,
        dense: true,
        onPressed: onBack,
      ),
      sections: [
        if (section != null)
          RankGroupSection(
            title: section.fellowshipName,
            icon: LucideIcons.users,
            rows: section.rows,
            emptyTitle: 'Nothing ranked yet',
            emptyMessage:
                'Rankings appear once entries are approved for this fellowship.',
            trailing:
                '${section.rows.length} partners · ${money(section.totalCedis)}',
          ),
      ],
      requireAnyRows: section != null && section.rows.isNotEmpty,
    );
  }
}


/// Everything you can do to a fellowship, in one place (Hick: nothing else
/// on the row competes with opening it).
class _FellowshipMenu extends ConsumerWidget {
  const _FellowshipMenu({required this.name, required this.partners});

  final String name;
  final int partners;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    PopupMenuItem<String> item(String v, IconData icon, String label, String hint) => PopupMenuItem(
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 16, color: Sel.ink),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: SelType.bodyMedium.copyWith(color: Sel.ink)),
                Text(hint, style: SelType.small),
              ],
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      width: 40,
      height: 40,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'More for $name',
        icon: const Icon(LucideIcons.moreHorizontal, size: 18, color: Sel.ink),
        color: Sel.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Sel.border),
        ),
        elevation: 0,
        onSelected: (v) {
          switch (v) {
            case 'move':
              context.go('/fellowships/move?from=${Uri.encodeQueryComponent(name)}');
            case 'rename':
              renameFellowship(context, ref, name);
            case 'merge':
              mergeFellowship(context, ref, name);
            case 'close':
              closeFellowship(context, ref, name);
          }
        },
        itemBuilder: (_) => [
          if (partners > 0) item('move', LucideIcons.arrowLeftRight, 'Move people…', 'Tick who goes, then pick where'),
          item('rename', LucideIcons.pencil, 'Rename…', 'Everyone stays; the name changes'),
          if (partners > 0) item('merge', LucideIcons.gitMerge, 'Merge into…', partners == 1 ? 'Its 1 partner joins another fellowship' : 'All $partners join another fellowship'),
          const PopupMenuDivider(),
          item('close', LucideIcons.ban, 'Close fellowship…', partners > 0 ? 'Move its people first' : 'It is empty'),
        ],
      ),
    );
  }
}

/// What the fellowships look like at a glance, before the list.
class _FellowshipSummary extends ConsumerWidget {
  const _FellowshipSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partners = [
      for (final p in ref.watch(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[])
        if (p.isActive) p,
    ];
    final known = ref.watch(knownFellowshipsProvider);
    final pastor = ref.watch(userChurchIndexProvider).valueOrNull?.isPastor ?? false;
    final view = ref.watch(givingViewProvider);
    final money = ref.watch(churchMoneyFormatProvider);
    final period = ref.watch(activePeriodProvider)?.name;

    final sizes = [
      for (final f in known) (f, partners.where((p) => fellowshipNamesMatch(p.fellowship, f)).length),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final empty = sizes.where((s) => s.$2 == 0).length;
    final none = partners.where((p) => p.fellowship.trim().isEmpty).length;
    final largest = sizes.isEmpty ? null : sizes.first;
    final smallest = sizes.where((s) => s.$2 > 0).lastOrNull;
    final top = [...view.fellowships]..sort((a, b) => b.total.compareTo(a.total));
    final topGiving = top.where((f) => f.total > 0).firstOrNull;

    final tiles = <(String, String, String?, VoidCallback?)>[
      ('Fellowships', '${known.length}', empty == 0 ? 'Every one has people' : '$empty empty · you can close ${empty == 1 ? 'it' : 'them'}', null),
      ('Partners', '${partners.length}', none == 0 ? 'Everyone is in a fellowship' : '$none with no fellowship', none == 0 ? null : () => context.go('/tools/move')),
      ('Largest', largest == null ? '—' : largest.$1, largest == null ? null : '${largest.$2} partners${smallest != null && smallest.$1 != largest.$1 ? ' · smallest ${smallest.$1}, ${smallest.$2}' : ''}', null),
      if (pastor)
        ('Most giving${period == null ? '' : ' · $period'}', topGiving?.name ?? '—', topGiving == null ? 'No approved giving yet' : money(topGiving.total), null)
      else
        ('Average size', known.isEmpty ? '—' : (partners.length / known.length).toStringAsFixed(0), 'partners per fellowship', null),
    ];
    // A phone gets the four as a tight two-by-two, so the list is not pushed
    // a screen down; wider screens get the usual stat cards.
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 600) {
          return SelStatRow(
            stats: [
              for (final (label, value, note, tap) in tiles)
                SelStat(label: label, value: value, footnote: note, onTap: tap),
            ],
          );
        }
        final w = (c.maxWidth - SelSpace.x3) / 2;
        return Wrap(
          spacing: SelSpace.x3,
          runSpacing: SelSpace.x3,
          children: [
            for (final (label, value, note, tap) in tiles)
              SizedBox(
                width: w,
                child: SelCard(
                  onTap: tap,
                  padding: const EdgeInsets.all(SelSpace.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: SelType.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: SelSpace.x1),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SelType.subtitle.copyWith(color: Sel.ink, fontWeight: FontWeight.w800)),
                      if (note != null)
                        Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: SelType.small),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
