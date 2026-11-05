import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/panel_flows.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/partners/providers/partners_providers.dart';

/// Partners · All partners — the directory. Ranked is its own destination now
/// (`/ranked`), straight after Partners in the sidebar.
class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  bool _includeInactive = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final partnersAsync = ref.watch(partnersStreamProvider(_includeInactive));

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(partnersStreamProvider(_includeInactive));
        ref.invalidate(rankingEntriesProvider);
        invalidateEntryDerivedData(ref);
      },
      children: [
        SelPageTitle(
          title: 'All partners',
          subtitle: 'Everyone with a giving record in your church.',
          actions: [
            SelButton.cyan(
              label: 'Add partner',
              icon: LucideIcons.plus,
              onPressed: idx == null
                  ? null
                  : () => showPartnerFormPanel(
                      context,
                      churchId: idx.churchId,
                      uid: idx.uid,
                    ),
            ),
          ],
        ),

        Row(
          children: [
            SizedBox(
              width: 280,
              child: SelField(
                hint: 'Search name or member ID',
                prefixIcon: LucideIcons.search,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: SelSpace.x3),
            SelButton(
              label: _includeInactive ? 'Hide inactive' : 'Show inactive',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: () =>
                  setState(() => _includeInactive = !_includeInactive),
            ),
          ],
        ),

        const SizedBox(height: SelSpace.x6),

        partnersAsync.when(
          loading: () => const SelCard(child: SelSkeletonRows()),
          error: (e, _) => SelError(message: '$e'),
          data: (partners) {
            final rows = partners.where((p) {
              if (_query.isEmpty) return true;
              return p.fullName.toLowerCase().contains(_query) ||
                  p.memberId.toLowerCase().contains(_query) ||
                  p.fellowship.toLowerCase().contains(_query);
            }).toList();

            return SelLedger.builder(
              minWidth: 720,
              maxVirtualHeight: 640,
              columns: const [
                SelColumn('Member ID', fit: SelColFit.fixed, width: 120),
                SelColumn('Name', flex: 3),
                SelColumn('Fellowship', flex: 2),
                SelColumn.numeric('Total given', width: 140),
                SelColumn('Status', fit: SelColFit.fixed, width: 110),
              ],
              emptyState: SelEmpty(
                title: _query.isEmpty ? 'No partners yet' : 'No matches',
                message: _query.isEmpty
                    ? 'Add partners to start recording their giving.'
                    : 'Nothing matches “$_query”.',
              ),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final p = rows[i];
                return SelRow(
                  onTap: () => context.go('/partners/${p.id}'),
                  cells: [
                    SelCell.secondary(p.memberId),
                    SelCell.primary(p.fullName),
                    SelCell.secondary(p.fellowship),
                    SelCell.numeric(money(p.totalApprovedAmount)),
                    SelStatusMark(
                      status: p.isActive
                          ? SelStatus.active
                          : SelStatus.inactive,
                      label: p.isActive ? 'Active' : 'Inactive',
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}
