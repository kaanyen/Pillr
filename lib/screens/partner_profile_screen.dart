import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/partners/presentation/partner_form_dialog.dart';
import '../features/partners/providers/partners_providers.dart';
import '../features/periods/domain/partnership_period.dart';
import '../features/periods/providers/periods_providers.dart';
import 'arm_palette.dart';

/// One partner: who they are, what they have given, and every entry.
class PartnerProfileScreen extends ConsumerStatefulWidget {
  const PartnerProfileScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  ConsumerState<PartnerProfileScreen> createState() =>
      _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends ConsumerState<PartnerProfileScreen> {
  String? _periodFilter;
  String? _armFilter;

  /// Given in at least three consecutive periods. Shown as a quiet tag rather
  /// than a badge — it is a fact about the record, not an award.
  bool _recurring(List<PartnershipPeriod> periods, List<PartnershipEntry> entries) {
    final approved = entries.where((e) => e.status == 'approved');
    if (approved.isEmpty) return false;
    final has = approved.map((e) => e.partnershipPeriodId).toSet();
    final ordered = [...periods]..sort((a, b) => a.startDate.compareTo(b.startDate));
    var run = 0, best = 0;
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

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final partnerAsync = ref.watch(partnerStreamProvider(widget.partnerId));
    final entriesAsync = ref.watch(partnerEntriesProvider(widget.partnerId));
    final periods = ref.watch(periodsStreamProvider).valueOrNull ?? [];
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];

    String periodName(String id) =>
        periods.where((p) => p.id == id).firstOrNull?.name ?? id;
    String armName(String id) =>
        arms.where((a) => a.id == id).firstOrNull?.name ?? id;

    return partnerAsync.when(
      loading: () => const SelPageBody(
        children: [SelCard(child: SelSkeletonRows(count: 4))],
      ),
      error: (e, _) => SelPageBody(children: [SelError(message: '$e')]),
      data: (partner) {
        if (partner == null) {
          return SelPageBody(
            children: [
              SelEmpty(
                title: 'Partner not found',
                message: 'This record may have been removed.',
                actionLabel: 'Back to partners',
                onAction: () => context.go('/partners'),
              ),
            ],
          );
        }

        final all = entriesAsync.valueOrNull ?? [];
        final rows = all.where((e) {
          if (_periodFilter != null && e.partnershipPeriodId != _periodFilter) {
            return false;
          }
          if (_armFilter != null && e.partnershipArmId != _armFilter) return false;
          return true;
        }).toList();

        final approved = all.where((e) => e.status == 'approved').toList();
        final pending = all.where((e) => e.status == 'pending').length;
        final isRecurring = _recurring(periods, all);

        return SelPageBody(
          onRefresh: () async =>
              ref.invalidate(partnerEntriesProvider(widget.partnerId)),
          children: [
            SelPageTitle(
              title: partner.fullName,
              subtitle: [
                partner.memberId,
                partner.fellowship,
                if (isRecurring) 'Recurring partner',
              ].where((e) => e.isNotEmpty).join(' · '),
              actions: [
                if (idx?.isPastor == true)
                  SelButton(
                    label: 'Edit',
                    icon: LucideIcons.pencil,
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => PartnerFormDialog(
                        churchId: idx!.churchId,
                        uid: idx.uid,
                        existing: partner,
                      ),
                    ),
                  ),
                SelButton(
                  label: 'Back',
                  kind: SelButtonKind.quiet,
                  onPressed: () => context.go('/partners'),
                ),
              ],
            ),

            SelStatRow(stats: [
              SelStat(
                label: 'Total approved',
                value: ref.watch(churchCompactMoneyProvider)(
                  partner.totalApprovedAmount,
                ),
                exactValue: money(partner.totalApprovedAmount),
                footnote: '${approved.length} entries',
              ),
              SelStat(
                label: 'Awaiting review',
                value: '$pending',
                footnote: pending == 0 ? 'Nothing pending' : 'In the queue',
              ),
              SelStat(
                label: 'Status',
                value: partner.isActive ? 'Active' : 'Inactive',
                footnote: partner.fellowship.isEmpty
                    ? 'No fellowship'
                    : partner.fellowship,
              ),
            ]),

            const SelSectionGap(factor: 0.4),

            if (partner.phone != null || partner.email != null) ...[
              SelPanel(
                title: 'Contact',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (partner.phone != null && partner.phone!.isNotEmpty)
                      _Contact(LucideIcons.phone, partner.phone!),
                    if (partner.email != null && partner.email!.isNotEmpty)
                      _Contact(LucideIcons.mail, partner.email!),
                  ],
                ),
              ),
              const SizedBox(height: SelSpace.x4),
            ],

            Row(
              children: [
                Expanded(child: SelSectionLabel(label: 'Giving history')),
                if (periods.isNotEmpty)
                  SizedBox(
                    width: 170,
                    child: SelSelect<String?>(
                      value: _periodFilter,
                      onChanged: (v) => setState(() => _periodFilter = v),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All periods'),
                        ),
                        for (final p in periods)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                    ),
                  ),
                const SizedBox(width: SelSpace.x2),
                if (arms.isNotEmpty)
                  SizedBox(
                    width: 170,
                    child: SelSelect<String?>(
                      value: _armFilter,
                      onChanged: (v) => setState(() => _armFilter = v),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All arms'),
                        ),
                        for (final a in arms)
                          DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: SelSpace.x3),

            SelLedger(
              minWidth: 620,
              columns: const [
                SelColumn('Arm', flex: 2),
                SelColumn('Period', flex: 2),
                SelColumn.numeric('Amount', width: 130),
                SelColumn('Status', fit: SelColFit.fixed, width: 120),
                SelColumn('Date', fit: SelColFit.fixed, width: 110),
              ],
              emptyState: const SelEmpty(
                title: 'No giving recorded',
                message: 'Entries for this partner will appear here.',
              ),
              rows: [
                for (final e in rows)
                  SelRow(
                    onTap: () => context.go('/entries/${e.id}'),
                    cells: [
                      ArmLabel(
                        armId: e.partnershipArmId,
                        name: armName(e.partnershipArmId),
                        style: SelType.bodyMedium,
                      ),
                      SelCell.secondary(periodName(e.partnershipPeriodId)),
                      SelCell.numeric(
                        money(e.amountCedis),
                        tone: switch (e.status) {
                          'approved' => SelTone.positive,
                          'declined' => SelTone.negative,
                          _ => SelTone.neutral,
                        },
                      ),
                      SelStatusMark.fromString(
                        status: e.status,
                        label: e.status[0].toUpperCase() + e.status.substring(1),
                      ),
                      SelCell.secondary(
                        formatFirestoreDate(e.dateGiven, pattern: 'd MMM'),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact(this.icon, this.value);

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SelSpace.x2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Sel.ash),
          const SizedBox(width: SelSpace.x2),
          Text(value, style: SelType.body),
        ],
      ),
    );
  }
}
