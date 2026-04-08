import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/fade_in_once.dart';
import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../entries/providers/entries_providers.dart';
import '../providers/dashboard_stats_providers.dart';

class StaffDashboardScreen extends ConsumerWidget {
  const StaffDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(staffMyEntryStatsProvider);
    final entries = ref.watch(entriesListProvider).valueOrNull ?? [];
    final declined = entries.where((e) => e.status == 'declined').length;
    final recent = [...entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recent10 = recent.take(10).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(entriesListProvider);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('My dashboard', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Live totals from your submitted entries.',
            style: AppTypography.body,
          ),
          if (declined > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Material(
              color: const Color(0xFFFFF4E6),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFB45309)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '$declined entr${declined == 1 ? 'y' : 'ies'} need attention (declined). Open Entries to review.',
                        style: AppTypography.caption.copyWith(color: const Color(0xFFB45309)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          PillrButton(
            label: 'New entry',
            expanded: true,
            onPressed: () => context.go('/entries/new'),
            variant: PillrButtonVariant.primary,
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, c) {
              final cross = c.maxWidth > 700 ? 2 : 1;
              return GridView.count(
                crossAxisCount: cross,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.45,
                children: [
                  FadeInOnce(
                    delay: Duration.zero,
                    child: PillrStatCard(
                      label: 'My entries',
                      valueText: '${s.totalCount}',
                      periodLabel: 'All statuses',
                    ),
                  ),
                  FadeInOnce(
                    delay: const Duration(milliseconds: 60),
                    child: PillrStatCard(
                      label: 'My approved total',
                      valueText: formatCedis(s.approvedTotalCedis),
                      periodLabel: '${s.approvedCount} approved',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('My recent entries', style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          if (recent10.isEmpty)
            Text('No entries yet.', style: AppTypography.caption)
          else
            ...recent10.map(
              (e) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(formatCedis(e.amountCedis), style: AppTypography.body),
                subtitle: Text(
                  '${e.dateGiven.year}-${e.dateGiven.month.toString().padLeft(2, '0')}-${e.dateGiven.day.toString().padLeft(2, '0')} · ${e.partnerSnapshot['fullName'] ?? 'Partner'}',
                  style: AppTypography.caption,
                ),
                trailing: _statusBadge(e.status),
                onTap: () => context.go('/entries/${e.id}'),
              ),
            ),
        ],
      ),
      ),
    );
  }

  static Widget _statusBadge(String s) {
    switch (s) {
      case 'approved':
        return const PillrBadge(label: 'Approved', kind: PillrBadgeKind.approved, compact: true);
      case 'declined':
        return const PillrBadge(label: 'Declined', kind: PillrBadgeKind.inactive, compact: true);
      default:
        return const PillrBadge(label: 'Pending', kind: PillrBadgeKind.pending, compact: true);
    }
  }
}
