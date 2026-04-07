import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/domain/partnership_entry.dart';
import '../../entries/providers/entries_providers.dart';
import '../providers/partners_providers.dart';
import 'partner_form_dialog.dart';

class PartnerProfileScreen extends ConsumerWidget {
  const PartnerProfileScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(partnerStreamProvider(partnerId));
    final entriesAsync = ref.watch(partnerEntriesProvider(partnerId));
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;

    return partnerAsync.when(
      loading: () => const Center(child: PillrLoadingShimmer(height: 120)),
      error: (e, _) => PillrErrorState(message: e.toString(), onRetry: () {}),
      data: (partner) {
        if (partner == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Partner not found', style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.md),
                TextButton(onPressed: () => context.go('/partners'), child: const Text('Back to partners')),
              ],
            ),
          );
        }
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
                        Text(partner.fullName, style: AppTypography.heading2),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '${partner.memberId} · ${partner.fellowship}',
                          style: AppTypography.body,
                        ),
                      ],
                    ),
                  ),
                  if (idx != null && idx.isPastor)
                    PillrButton(
                      label: 'Edit',
                      variant: PillrButtonVariant.secondary,
                      onPressed: () async {
                        await showDialog<void>(
                          context: context,
                          builder: (ctx) => PartnerFormDialog(
                            churchId: idx.churchId,
                            uid: idx.uid,
                            existing: partner,
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  if (partner.email != null && partner.email!.isNotEmpty)
                    Text('Email: ${partner.email}', style: AppTypography.caption),
                  if (partner.phone != null && partner.phone!.isNotEmpty)
                    Text('Phone: ${partner.phone}', style: AppTypography.caption),
                  Text('Lifetime approved: ${formatCedis(partner.totalApprovedAmount)}', style: AppTypography.caption),
                  partner.isActive
                      ? const PillrBadge(label: 'Active', kind: PillrBadgeKind.approved, compact: true)
                      : const PillrBadge(label: 'Inactive', kind: PillrBadgeKind.inactive, compact: true),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Giving history', style: AppTypography.heading3),
              const SizedBox(height: AppSpacing.md),
              entriesAsync.when(
                loading: () => const PillrLoadingShimmer(height: 160),
                error: (e, _) => Text(e.toString(), style: AppTypography.caption),
                data: (entries) {
                  if (entries.isEmpty) {
                    return Text('No entries yet.', style: AppTypography.body);
                  }
                  return PillrDataTable(
                    minWidth: 600,
                    columns: [
                      DataColumn2(label: Text('DATE', style: AppTypography.tableHeader)),
                      DataColumn2(label: Text('AMOUNT', style: AppTypography.tableHeader)),
                      DataColumn2(label: Text('STATUS', style: AppTypography.tableHeader)),
                      DataColumn2(label: Text('', style: AppTypography.tableHeader), fixedWidth: 80),
                    ],
                    rows: [
                      for (final e in entries)
                        DataRow(
                          cells: [
                            DataCell(Text(_fmt(e), style: AppTypography.body)),
                            DataCell(Text(formatCedis(e.amountCedis), style: AppTypography.body)),
                            DataCell(_statusBadge(e.status)),
                            DataCell(
                              TextButton(
                                onPressed: () => context.go('/entries/${e.id}'),
                                child: const Text('Open'),
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
      },
    );
  }

  static String _fmt(PartnershipEntry e) {
    final d = e.dateGiven;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
