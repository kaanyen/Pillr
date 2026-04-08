import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_entity_card.dart';
import '../../../common/widgets/pillr_form_card.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/domain/partnership_entry.dart';
import '../../entries/providers/entries_providers.dart';
import '../../periods/domain/partnership_period.dart';
import '../../periods/providers/periods_providers.dart';
import '../providers/partners_providers.dart';
import 'partner_form_dialog.dart';

class PartnerProfileScreen extends ConsumerStatefulWidget {
  const PartnerProfileScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  ConsumerState<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends ConsumerState<PartnerProfileScreen> {
  String? _periodFilter;
  String? _armFilter;

  bool _recurringPartner(
    List<PartnershipPeriod> periods,
    List<PartnershipEntry> entries,
  ) {
    final approved = entries.where((e) => e.status == 'approved').toList();
    if (approved.isEmpty) return false;
    final has = <String>{};
    for (final e in approved) {
      has.add(e.partnershipPeriodId);
    }
    final ordered = [...periods]..sort((a, b) => a.startDate.compareTo(b.startDate));
    var run = 0;
    var best = 0;
    for (final p in ordered) {
      if (has.contains(p.id)) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best >= 3;
  }

  List<PartnershipEntry> _filtered(
    List<PartnershipEntry> entries,
  ) {
    return entries.where((e) {
      if (_periodFilter != null && e.partnershipPeriodId != _periodFilter) return false;
      if (_armFilter != null && e.partnershipArmId != _armFilter) return false;
      return true;
    }).toList();
  }

  String _periodLabel(String id, List<PartnershipPeriod> periods) {
    for (final p in periods) {
      if (p.id == id) return p.name;
    }
    return id;
  }

  String _armLabel(String id, List<PartnershipArm> arms) {
    for (final a in arms) {
      if (a.id == id) return a.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final partnerAsync = ref.watch(partnerStreamProvider(widget.partnerId));
    final entriesAsync = ref.watch(partnerEntriesProvider(widget.partnerId));
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final periodsAsync = ref.watch(periodsStreamProvider);
    final armsAsync = ref.watch(armsStreamProvider);

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
        final staffApprovedTotal = ref.watch(staffApprovedTotalForPartnerProvider(partner.id));

        return periodsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (periods) {
            return armsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (arms) {
                return entriesAsync.when(
                  loading: () => const Center(child: PillrLoadingShimmer(height: 160)),
                  error: (e, _) => Text(e.toString(), style: AppTypography.caption),
                  data: (entries) {
                    final recurring = _recurringPartner(periods, entries);
                    final filtered = _filtered(entries);
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
                              Text(
                                idx?.isStaff == true
                                    ? 'Your approved total: ${formatCedis(staffApprovedTotal)}'
                                    : 'Lifetime approved: ${formatCedis(partner.totalApprovedAmount)}',
                                style: AppTypography.caption,
                              ),
                              partner.isActive
                                  ? const PillrBadge(label: 'Active', kind: PillrBadgeKind.approved, compact: true)
                                  : const PillrBadge(label: 'Inactive', kind: PillrBadgeKind.inactive, compact: true),
                              if (recurring)
                                const PillrBadge(
                                  label: 'Recurring partner',
                                  kind: PillrBadgeKind.approved,
                                  compact: true,
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.sm,
                            children: [
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<String?>(
                                  key: ValueKey('pp-period-$_periodFilter'),
                                  initialValue: _periodFilter,
                                  decoration: const InputDecoration(
                                    labelText: 'Period',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(value: null, child: Text('All periods')),
                                    for (final p in periods)
                                      DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                                  ],
                                  onChanged: (v) => setState(() => _periodFilter = v),
                                ),
                              ),
                              SizedBox(
                                width: 200,
                                child: DropdownButtonFormField<String?>(
                                  key: ValueKey('pp-arm-$_armFilter'),
                                  initialValue: _armFilter,
                                  decoration: const InputDecoration(
                                    labelText: 'Arm',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(value: null, child: Text('All arms')),
                                    for (final a in arms)
                                      DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                                  ],
                                  onChanged: (v) => setState(() => _armFilter = v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          PillrFormCard(
                            title: 'Giving history',
                            child: filtered.isEmpty
                                ? Text('No entries for this filter.', style: AppTypography.body)
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      final useCards = PillrLayout.useCardListLayout(constraints.maxWidth);
                                      final table = PillrDataTable(
                                        minWidth: 720,
                                        columns: [
                                          DataColumn2(label: Text('DATE', style: AppTypography.tableHeader)),
                                          DataColumn2(label: Text('PERIOD', style: AppTypography.tableHeader)),
                                          DataColumn2(label: Text('ARM', style: AppTypography.tableHeader)),
                                          DataColumn2(label: Text('AMOUNT', style: AppTypography.tableHeader)),
                                          DataColumn2(label: Text('STATUS', style: AppTypography.tableHeader)),
                                          DataColumn2(label: Text('', style: AppTypography.tableHeader), fixedWidth: 80),
                                        ],
                                        rows: [
                                          for (final e in filtered)
                                            DataRow(
                                              cells: [
                                                DataCell(Text(_fmt(e), style: AppTypography.body)),
                                                DataCell(Text(_periodLabel(e.partnershipPeriodId, periods), style: AppTypography.body)),
                                                DataCell(Text(_armLabel(e.partnershipArmId, arms), style: AppTypography.body)),
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
                                      final cards = Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          for (final e in filtered)
                                            PillrEntityCard(
                                              title: formatCedis(e.amountCedis),
                                              subtitle:
                                                  '${_fmt(e)} · ${_periodLabel(e.partnershipPeriodId, periods)} · ${_armLabel(e.partnershipArmId, arms)}',
                                              trailing: _statusBadge(e.status),
                                              footer: Align(
                                                alignment: Alignment.centerRight,
                                                child: TextButton(
                                                  onPressed: () => context.go('/entries/${e.id}'),
                                                  child: const Text('Open'),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                      return useCards ? cards : table;
                                    },
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
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
