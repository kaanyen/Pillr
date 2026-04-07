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
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../auth/providers/auth_providers.dart';
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
  bool _includeInactive = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final partners = ref.watch(partnersStreamProvider(_includeInactive));
    final width = MediaQuery.sizeOf(context).width;
    final q = _search.text.trim().toLowerCase();

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
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilterChip(
                label: const Text('Show inactive'),
                selected: _includeInactive,
                onSelected: (v) => setState(() => _includeInactive = v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          partners.when(
            loading: () => const PillrLoadingShimmer(height: 200),
            error: (e, _) => PillrErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(partnersStreamProvider(_includeInactive)),
            ),
            data: (all) {
              final rows = q.isEmpty
                  ? all
                  : all.where((p) {
                      return p.memberId.toLowerCase().contains(q) ||
                          p.fullName.toLowerCase().contains(q) ||
                          p.fellowship.toLowerCase().contains(q);
                    }).toList();
              if (rows.isEmpty) {
                return PillrEmptyState(
                  title: 'No partners match',
                  message: q.isEmpty ? 'Add a partner to use them when recording entries.' : 'Try a different search.',
                  actionLabel: q.isEmpty ? 'Add partner' : null,
                  onAction: q.isEmpty && idx != null ? () => _openForm(idx.churchId, idx.uid, null) : null,
                );
              }
              return PillrDataTable(
                minWidth: width > 800 ? width - AppSpacing.lg * 2 : 900,
                columns: [
                  DataColumn2(
                    label: Text('MEMBER ID', style: AppTypography.tableHeader),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(label: Text('NAME', style: AppTypography.tableHeader), size: ColumnSize.L),
                  DataColumn2(label: Text('FELLOWSHIP', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('TOTAL ₵', style: AppTypography.tableHeader)),
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
                        DataCell(Text(formatCedis(p.totalApprovedAmount), style: AppTypography.body)),
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
                              if (idx != null && idx.isPastor)
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
            },
          ),
        ],
      ),
    );
  }
}
