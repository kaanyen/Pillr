import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/entries_providers.dart';

class EntriesListScreen extends ConsumerWidget {
  const EntriesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final entries = ref.watch(entriesListProvider);
    final width = MediaQuery.sizeOf(context).width;

    return SingleChildScrollView(
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
                    Text(
                      idx?.isPastor == true ? 'Entries' : 'My entries',
                      style: AppTypography.heading2,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      idx?.isPastor == true
                          ? 'All recorded giving for your church.'
                          : 'Entries you created (pending until the pastor approves).',
                      style: AppTypography.body,
                    ),
                  ],
                ),
              ),
              if (idx != null && (idx.isPastor || idx.isStaff))
                PillrButton(
                  label: '+ New entry',
                  icon: Icons.add,
                  onPressed: () => context.go('/entries/new'),
                  variant: PillrButtonVariant.primary,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          entries.when(
            loading: () => const PillrLoadingShimmer(height: 200),
            error: (e, _) => PillrErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(entriesListProvider),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return PillrEmptyState(
                  title: 'No entries yet',
                  message: 'Record a new partnership entry.',
                  actionLabel: 'New entry',
                  onAction: idx != null && (idx.isPastor || idx.isStaff)
                      ? () => context.go('/entries/new')
                      : null,
                );
              }
              return PillrDataTable(
                minWidth: width > 800 ? width - AppSpacing.lg * 2 : 880,
                sortColumnIndex: 0,
                sortAscending: false,
                columns: [
                  DataColumn2(label: Text('PARTNER', style: AppTypography.tableHeader), size: ColumnSize.L),
                  DataColumn2(label: Text('AMOUNT', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('STATUS', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('SUBMITTED', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('', style: AppTypography.tableHeader), fixedWidth: 72),
                ],
                rows: [
                  for (final e in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(
                          e.partnerSnapshot['fullName']?.toString() ?? '—',
                          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                        )),
                        DataCell(Text(formatCedis(e.amountCedis), style: AppTypography.body)),
                        DataCell(_statusBadge(e.status)),
                        DataCell(Text(
                          '${e.createdAt.year}-${e.createdAt.month.toString().padLeft(2, '0')}-${e.createdAt.day.toString().padLeft(2, '0')}',
                          style: AppTypography.caption,
                        )),
                        DataCell(
                          TextButton(
                            onPressed: () => context.go('/entries/${e.id}'),
                            child: const Text('View'),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
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
