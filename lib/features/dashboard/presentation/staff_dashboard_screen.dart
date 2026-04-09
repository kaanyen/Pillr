import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../common/widgets/fade_in_once.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../entries/domain/partnership_entry.dart';
import '../../entries/providers/entries_providers.dart';
import '../providers/dashboard_stats_providers.dart';
import '../widgets/dashboard_shared.dart';

class StaffDashboardScreen extends ConsumerWidget {
  const StaffDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(staffMyEntryStatsProvider);
    final entries = ref.watch(entriesListProvider).valueOrNull ?? [];
    final declined = entries.where((e) => e.status == 'declined').length;
    final recent = [...entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recent10 = recent.take(10).toList();
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final churchName = ref.watch(churchNameProvider) ?? 'your church';

    final nameParts = profile?.fullName.trim().split(RegExp(r'\s+')) ?? <String>[];
    final firstName =
        nameParts.isEmpty ? 'there' : TextCaseUtils.toTitleCase(nameParts.first);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(entriesListProvider);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 640;
                final welcome = DashboardWelcomeBlock(
                  firstName: firstName,
                  subtitle:
                      'Here\'s your submission activity at $churchName — create entries and track approvals.',
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      welcome,
                      const SizedBox(height: AppSpacing.md),
                      PillrButton(
                        label: 'New entry',
                        icon: LucideIcons.plus,
                        variant: PillrButtonVariant.primary,
                        expanded: true,
                        onPressed: () => context.go('/entries/new'),
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: welcome),
                    PillrButton(
                      label: 'New entry',
                      icon: LucideIcons.plus,
                      variant: PillrButtonVariant.primary,
                      onPressed: () => context.go('/entries/new'),
                    ),
                  ],
                );
              },
            ),
            if (declined > 0) ...[
              const SizedBox(height: AppSpacing.lg),
              Material(
                color: const Color(0xFFFFF4E6),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.info, color: Color(0xFFB45309)),
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
            const SizedBox(height: AppSpacing.xl),
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
                        backgroundColor: DashboardTints.totalBg,
                        iconCircleColor: DashboardTints.totalIconCircle,
                        iconColor: AppColors.primaryColor,
                        icon: LucideIcons.fileText,
                      ),
                    ),
                    FadeInOnce(
                      delay: const Duration(milliseconds: 60),
                      child: PillrStatCard(
                        label: 'My approved total',
                        valueText: formatCedis(s.approvedTotalCedis),
                        periodLabel: '${s.approvedCount} approved',
                        backgroundColor: DashboardTints.partnersBg,
                        iconCircleColor: DashboardTints.partnersIconCircle,
                        iconColor: AppColors.navActiveForeground,
                        icon: LucideIcons.checkCircle,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('My recent entries', style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.md),
            PillrCard(
              padding: EdgeInsets.zero,
              child: recent10.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'No entries yet.',
                        style: AppTypography.body.copyWith(color: AppColors.gray400),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < recent10.length; i++)
                          _StaffEntryRow(
                            entry: recent10[i],
                            showDivider: i < recent10.length - 1,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _staffEntryStatusBadge(String s) {
  switch (s) {
    case 'approved':
      return const PillrBadge(label: 'Approved', kind: PillrBadgeKind.approved, compact: true);
    case 'declined':
      return const PillrBadge(label: 'Declined', kind: PillrBadgeKind.inactive, compact: true);
    default:
      return const PillrBadge(label: 'Pending', kind: PillrBadgeKind.pending, compact: true);
  }
}

class _StaffEntryRow extends StatelessWidget {
  const _StaffEntryRow({
    required this.entry,
    required this.showDivider,
  });

  final PartnershipEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final partnerRaw = entry.partnerSnapshot['fullName']?.toString() ?? 'Partner';
    final partner = TextCaseUtils.toTitleCase(partnerRaw);
    final dateStr =
        '${entry.dateGiven.year}-${entry.dateGiven.month.toString().padLeft(2, '0')}-${entry.dateGiven.day.toString().padLeft(2, '0')}';

    return Column(
      children: [
        InkWell(
          onTap: () => context.go('/entries/${entry.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatCedis(entry.amountCedis),
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.gray900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dateStr · $partner',
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                _staffEntryStatusBadge(entry.status),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: AppColors.gray200),
      ],
    );
  }
}
