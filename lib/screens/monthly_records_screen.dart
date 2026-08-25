import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../design/seline.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/entries/providers/monthly_records_entries_provider.dart';
import '../l10n/app_localizations.dart';
import 'monthly_records_view.dart';

/// Records — browse approved giving grouped by month.
class MonthlyRecordsScreen extends ConsumerStatefulWidget {
  const MonthlyRecordsScreen({super.key});

  @override
  ConsumerState<MonthlyRecordsScreen> createState() =>
      _MonthlyRecordsScreenState();
}

class _MonthlyRecordsScreenState extends ConsumerState<MonthlyRecordsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final entriesState = ref.read(monthlyRecordsEntriesProvider);
    if (entriesState.loading ||
        entriesState.loadingMore ||
        !entriesState.hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      ref.read(monthlyRecordsEntriesProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = ref.watch(churchMoneyFormatProvider);
    final entriesState = ref.watch(monthlyRecordsEntriesProvider);
    final index = ref.watch(monthlyRecordsIndexProvider);

    return SelPageBody(
      controller: _scrollController,
      onRefresh: () async =>
          ref.read(monthlyRecordsEntriesProvider.notifier).refresh(),
      children: [
        SelPageTitle(
          title: l10n.recordsMonthlyTitle,
          subtitle: l10n.recordsMonthlySubtitle,
          actions: [
            SelButton(
              label: l10n.navRecordsAll,
              icon: LucideIcons.list,
              kind: SelButtonKind.quiet,
              onPressed: () => context.go('/records'),
            ),
          ],
        ),
        if (entriesState.error != null && entriesState.initialized)
          Padding(
            padding: const EdgeInsets.only(bottom: SelSpace.x4),
            child: SelError(
              message: entriesState.error!,
              onRetry: () =>
                  ref.read(monthlyRecordsEntriesProvider.notifier).refresh(),
            ),
          ),
        if (entriesState.loading && !entriesState.initialized)
          const SelCard(child: SelSkeletonRows())
        else
          MonthlyRecordsView(
            index: index,
            money: money,
            loadedEntryCount: entriesState.entries.length,
            hasMore: entriesState.hasMore,
            loadingMore: entriesState.loadingMore,
            onLoadMore: () =>
                ref.read(monthlyRecordsEntriesProvider.notifier).loadMore(),
          ),
      ],
    );
  }
}
