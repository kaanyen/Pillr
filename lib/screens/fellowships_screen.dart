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
import 'ranked_views.dart';
import 'record_filter_bar.dart';

enum _View { directory, ranked, manage }

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
          SelError(message: '$e'),
        ],
      );
    }
  }

  Widget _buildPage(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final canManage = idx?.canManageFellowships ?? false;
    final adminOnly = idx?.isAdmin ?? false;
    final view = adminOnly ? _View.manage : _view;
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
              : _summary(ref),
          actions: [
            if (canManage && view != _View.manage)
              SelButton.cyan(
                label: 'New fellowship',
                icon: LucideIcons.plus,
                onPressed: () => setState(() => _view = _View.manage),
              ),
            if (view == _View.manage && !adminOnly)
              SelButton(
                label: 'Back to the list',
                icon: LucideIcons.arrowLeft,
                onPressed: () => setState(() => _view = _View.directory),
              ),
          ],
        ),
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
        if (view == _View.directory)
          _FellowshipDirectory(
            query: _query,
            onOpenFellowship: _openFellowshipMembers,
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
  });

  final String query;
  final ValueChanged<String> onOpenFellowship;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(partnersStreamProvider(false));
    return partnersAsync.when(
      loading: () => const SelCard(child: SelSkeletonRows()),
      error: (e, _) => SelError(message: '$e'),
      data: (partners) => _directoryTable(ref, partners),
    );
  }

  Widget _directoryTable(WidgetRef ref, List<Partner> partners) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final rows = [
      for (final f in view.fellowships)
        if (query.isEmpty || f.name.toLowerCase().contains(query)) f,
    ];
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
          child: Text(place > 0 ? ordinal(place) : '', style: SelType.small),
        ),
      ],
    );

    return SelLedger(
      minWidth: 200.0 + view.arms.length * 170 + 150,
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
              SelCell.primary(f.name),
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
      return SelError(message: '$e');
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
