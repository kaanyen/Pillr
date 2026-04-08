import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_entity_card.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/providers/entries_providers.dart';
import '../domain/partner.dart';
import '../providers/partners_providers.dart';
import 'partner_form_dialog.dart';

class PartnersListScreen extends ConsumerStatefulWidget {
  const PartnersListScreen({super.key});

  @override
  ConsumerState<PartnersListScreen> createState() => _PartnersListScreenState();
}

class _PartnersListScreenState extends ConsumerState<PartnersListScreen> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  bool _includeInactive = false;

  final List<Partner> _items = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  List<Partner>? _searchResults;
  bool _searching = false;
  bool _scheduledInitial = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchDebounced);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.removeListener(_onSearchDebounced);
    _search.dispose();
    super.dispose();
  }

  void _onSearchDebounced() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _runSearch();
    });
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    if (q.isEmpty) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      await _loadPartnersPagedFirst();
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final list = await ref.read(partnersRepositoryProvider).searchPartners(
            idx.churchId,
            q,
            includeInactive: _includeInactive,
          );
      if (!mounted) return;
      setState(() {
        _searchResults = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _searching = false;
      });
    }
  }

  void _ensureInitialLoad() {
    final i = ref.read(userChurchIndexProvider).valueOrNull;
    if (i == null || _scheduledInitial) return;
    _scheduledInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFirst();
    });
  }

  Future<void> _loadFirst() async {
    if (_search.text.trim().isNotEmpty) {
      await _runSearch();
      return;
    }
    await _loadPartnersPagedFirst();
  }

  Future<void> _loadPartnersPagedFirst() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(partnersRepositoryProvider).fetchPartnersPage(
            idx.churchId,
            includeInactive: _includeInactive,
            pageSize: 20,
          );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _search.text.trim().isNotEmpty) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(partnersRepositoryProvider).fetchPartnersPage(
            idx.churchId,
            includeInactive: _includeInactive,
            pageSize: 20,
            startAfter: _cursor,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openForm(String churchId, String uid, Partner? existing) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => PartnerFormDialog(
        churchId: churchId,
        uid: uid,
        existing: existing,
      ),
    );
    if (_search.text.trim().isNotEmpty) {
      await _runSearch();
    } else {
      await _loadFirst();
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final staffTotals = ref.watch(staffApprovedTotalsByPartnerProvider);
    final inSearch = _search.text.trim().isNotEmpty;

    ref.listen(userChurchIndexProvider, (prev, next) {
      final pc = prev?.valueOrNull?.churchId;
      final nc = next.valueOrNull?.churchId;
      if (pc != nc) {
        _items.clear();
        _cursor = null;
        _hasMore = true;
        _scheduledInitial = false;
        _searchResults = null;
        _ensureInitialLoad();
      }
    });

    if (idx != null) {
      _ensureInitialLoad();
    }

    final rows = inSearch ? (_searchResults ?? []) : _items;

    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Partners', style: AppTypography.heading2),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Members who give — search by member ID, name, or fellowship.',
                      style: AppTypography.body,
                    ),
                  ],
                ),
              ),
              PillrButton(
                label: '+ Add partner',
                icon: Icons.add,
                onPressed: idx == null ? null : () => _openForm(idx.churchId, idx.uid, null),
                variant: PillrButtonVariant.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: PillrTextField(
                  controller: _search,
                  label: 'Search',
                  hint: 'Member ID, name, fellowship…',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilterChip(
                label: const Text('Show inactive'),
                selected: _includeInactive,
                onSelected: (v) async {
                  setState(() => _includeInactive = v);
                  if (_search.text.trim().isNotEmpty) {
                    await _runSearch();
                  } else {
                    await _loadFirst();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (idx == null)
            const PillrLoadingShimmer(height: 200)
          else if (_loading || _searching)
            const PillrLoadingShimmer(height: 200)
          else if (_error != null)
            PillrErrorState(
              message: _error.toString(),
              onRetry: _loadFirst,
            )
          else if (rows.isEmpty)
            PillrEmptyState(
              title: 'No partners match',
              message: inSearch ? 'Try a different search.' : 'Add a partner to use them when recording entries.',
              actionLabel: inSearch ? null : 'Add partner',
              onAction: inSearch ? null : () => _openForm(idx.churchId, idx.uid, null),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final useCards = PillrLayout.useCardListLayout(constraints.maxWidth);
                final table = PillrDataTable(
                  minWidth: 900,
                  columns: [
                    DataColumn2(
                      label: Text('MEMBER ID', style: AppTypography.tableHeader),
                      size: ColumnSize.S,
                    ),
                    DataColumn2(label: Text('NAME', style: AppTypography.tableHeader), size: ColumnSize.L),
                    DataColumn2(label: Text('FELLOWSHIP', style: AppTypography.tableHeader)),
                    DataColumn2(
                      label: Text(
                        idx.isStaff == true ? 'YOUR TOTAL ₵' : 'TOTAL ₵',
                        style: AppTypography.tableHeader,
                      ),
                    ),
                    DataColumn2(label: Text('STATUS', style: AppTypography.tableHeader)),
                    DataColumn2(label: Text('ACTIONS', style: AppTypography.tableHeader), fixedWidth: 160),
                  ],
                  rows: [
                    for (final p in rows)
                      DataRow(
                        cells: [
                          DataCell(Text(p.memberId, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600))),
                          DataCell(
                            InkWell(
                              onTap: () => context.go('/partners/${p.id}'),
                              child: Text(p.fullName, style: AppTypography.body.copyWith(color: AppColors.primaryColor)),
                            ),
                          ),
                          DataCell(Text(p.fellowship, style: AppTypography.body)),
                          DataCell(
                            Text(
                              formatCedis(
                                idx.isStaff == true ? (staffTotals.valueOrNull?[p.id] ?? 0) : p.totalApprovedAmount,
                              ),
                              style: AppTypography.body,
                            ),
                          ),
                          DataCell(
                            p.isActive
                                ? const PillrBadge(label: 'Active', kind: PillrBadgeKind.approved, compact: true)
                                : const PillrBadge(label: 'Inactive', kind: PillrBadgeKind.inactive, compact: true),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => context.go('/partners/${p.id}'),
                                  child: const Text('View'),
                                ),
                                if (idx.isPastor)
                                  TextButton(
                                    onPressed: () => _openForm(idx.churchId, idx.uid, p),
                                    child: const Text('Edit'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                );
                final cardList = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in rows)
                      PillrEntityCard(
                        title: p.fullName,
                        subtitle: '${p.memberId} · ${p.fellowship} · ${formatCedis(idx.isStaff == true ? (staffTotals.valueOrNull?[p.id] ?? 0) : p.totalApprovedAmount)}',
                        trailing: p.isActive
                            ? const PillrBadge(label: 'Active', kind: PillrBadgeKind.approved, compact: true)
                            : const PillrBadge(label: 'Inactive', kind: PillrBadgeKind.inactive, compact: true),
                        footer: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppSpacing.sm,
                          children: [
                            TextButton(
                              onPressed: () => context.go('/partners/${p.id}'),
                              child: const Text('View'),
                            ),
                            if (idx.isPastor)
                              TextButton(
                                onPressed: () => _openForm(idx.churchId, idx.uid, p),
                                child: const Text('Edit'),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    useCards ? cardList : table,
                    if (!inSearch && _hasMore) ...[
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: PillrButton(
                          label: _loadingMore ? 'Loading…' : 'Load more',
                          onPressed: _loadingMore ? null : _loadMore,
                          variant: PillrButtonVariant.secondary,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
      ),
    );
  }
}
